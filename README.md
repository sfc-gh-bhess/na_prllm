# Example Native App that calls a service hosted on the Provider
This is a simple Native App that has a UDF that calls a 
service that is hosted on the Provider side (instead of on the
Consumer side). The sample service is a hosted Llama2 that 
will do a completion on a supplied prompt. There is only one
Function in the Native App, `app_public.prllm(STRING)`.

## Setup
There are 2 parts to set up, the Provider and the Consumer.

This example expects that both Provider has been
set up with the prerequisite steps to enable for Snowpark 
Container Services, specifically:
```
USE ROLE ACCOUNTADMIN;
CREATE SECURITY INTEGRATION IF NOT EXISTS snowservices_ingress_oauth
  TYPE=oauth
  OAUTH_CLIENT=snowservices_ingress
  ENABLED=true;
```

### Provider Setup
Before we proceed, you will need to get a HuggingFace API key.
See the HuggingFace documentarion for details.

For the Provider, we need to set up a few things:
* The LLM service
* The Native App to call the LLM service

#### Setup the LLM service
To create the LLM service, we need to create a few things:
* Role to run the service
* Compute pool to run the service
* Database and schema to hold the service objects
* Network Rule and External Access Integration to access HuggingFace
* Stage to hold specs and another for models for the service
* Image Repository to hold the images

```sql
CREATE ROLE IF NOT EXISTS prllm;
CREATE ROLE IF NOT EXISTS spcs_role;
GRANT ROLE spcs_role TO ROLE accountadmin;
GRANT BIND ENDPOINT ON ACCOUNT TO ROLE spcs_role;

CREATE COMPUTE POOL GPU_NV_S
  MIN_NODES = 1
  MAX_NODES = 1
  INSTANCE_FAMILY = GPU_NV_S;
GRANT usage, monitor ON COMPUTE POOL gpu_nv_s TO ROLE spcs_role;

GRANT CREATE DATABASE ON ACCOUNT TO ROLE spcs_role;
GRANT CREATE EXTERNAL ACCESS INTEGRATION TO ROLE spcs_role;
CREATE DATABASE IF NOT EXISTS spcs;
GRANT ALL ON DATABASE spcs TO ROLE spcs_role;
CREATE SCHEMA IF NOT EXISTS spcs.napp;
GRANT ALL ON SCHEMA spcs.napp TO ROLE spcs_role;

CREATE OR REPLACE NETWORK RULE spcs.napp.hf_network_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('huggingface.co', 'cdn-lfs.huggingface.co');
CREATE EXTERNAL ACCESS INTEGRATION hf_access_integration
    ALLOWED_NETWORK_RULES = ( spcs.napp.hf_network_rule )
    ENABLED = true;

USE ROLE spcs_role;
CREATE STAGE IF NOT EXISTS spcs.napp.models
    DIRECTORY = (ENABLE = TRUE)
    ENCRYPTION = (TYPE='SNOWFLAKE_SSE');
CREATE STAGE IF NOT EXISTS spcs.napp.specs
    DIRECTORY = (ENABLE = TRUE)
    ENCRYPTION = (TYPE='SNOWFLAKE_SSE');

CREATE IMAGE REPOSITORY spcs.napp.repo;
```
At this point, we need to get the URL for the image repository by
running `SHOW IMAGE REPOSITORIES` and copying the `repository_url` value.

At this point, we need to configure the various files that will
drive the building. To do so, run 
```
bash ./configure.sh
``` 

and answer the questions, entering in:
* The copied `repository_url` for the repository URL
* Your HuggingFace API key
* The database we are using, `SPCS`
* The schema we are using, `NAPP`

At this point, the `Makefile` and `llm.yaml` file will be created with
these values filled in.

Next, we need to build the 2 images, `llm` and `udf-flask`, and pushing
them to Snowflake. Do so by running 
```
make all
```

While that is building, you can upload the SPCS specification file
from `llm.yaml` to the stage `SPCS.NAPP.SPECS`.

Once the images have been pushed to Snowflake, we can finally create 
our LLM service:

```sql
USE ROLE spcs_role;
DROP SERVICE IF EXISTS spcs.napp.llama_2;
CREATE SERVICE spcs.napp.llama_2
    IN COMPUTE POOL gpu_nv_s
    FROM @spcs.napp.specs
    SPECIFICATION_FILE='llm.yaml'
    EXTERNAL_ACCESS_INTEGRATIONS = ( HF_ACCESS_INTEGRATION );

GRANT USAGE ON SERVICE spcs.napp.llama TO ROLE prllm;
```

To allow users to use the service, we can GRANT the role `prllm` 
to USERS and ROLES.

Now, we want to create a user that we will use to call
the exposed endpoint from the service. Create the user
and give it a password and grant that user the role `prllm`.
We will need the username and password in a later step, so
make a note of them.

We need to wait for the service to start. We can check its
status by running
```sql
USE ROLE spcs_role;
SELECT SYSTEM$GET_SERVICE_STATUS('spcs.napp.llama_2');
```

We are looking for a `READY` state.

Once the service has started, we will need to note the 
ingress URL for the service. To do so, run
```sql
USE ROLE spcs_role;
SHOW ENDPOINTS IN SERVICE spcs.napp.llama_2;
```
Make a note of the `chat` endpoint URL, as we will need it in 
a later step.

#### Setup the Native App.
Now let's set up the Native App. We will need a few things:
* A ROLE for the provider
* A STAGE to hold the files for the Native App
* An APPLICATION PACKAGE that defines the Native App
* A TABLE that will hold the credentials for accessing the Provider-side service

```sql
USE ROLE accountadmin;
CREATE ROLE IF NOT EXISTS nap_role;
GRANT ROLE nap_role TO ROLE accountadmin;
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE nap_role;
GRANT CREATE DATABASE ON ACCOUNT TO ROLE nap_role;
GRANT CREATE APPLICATION PACKAGE ON ACCOUNT TO ROLE nap_role;
GRANT CREATE APPLICATION ON ACCOUNT TO ROLE nap_role;
CREATE WAREHOUSE IF NOT EXISTS wh_nap WITH WAREHOUSE_SIZE='XSMALL';
GRANT ALL ON WAREHOUSE wh_nap TO ROLE nap_role;

USE ROLE nap_role;
CREATE DATABASE IF NOT EXISTS napp;
CREATE SCHEMA IF NOT EXISTS napp.napp;
CREATE STAGE IF NOT EXISTS napp.napp.app_stage;
DROP APPLICATION PACKAGE IF EXISTS na_prllm_pkg;
CREATE APPLICATION PACKAGE na_prllm_pkg;

CREATE SCHEMA na_prllm_pkg.shared_data;
CREATE TABLE na_prllm_pkg.shared_data.prllm_creds(host STRING, account STRING, user STRING, password STRING, api_url STRING, current_account STRING);
CREATE SECURE VIEW na_prllm_pkg.shared_data.prllm_creds_vw AS SELECT * FROM na_prllm_pkg.shared_data.prllm_creds WHERE current_account = current_account();
GRANT USAGE ON SCHEMA na_prllm_pkg.shared_data TO SHARE IN APPLICATION PACKAGE na_prllm_pkg;
GRANT SELECT ON VIEW na_prllm_pkg.shared_data.prllm_creds_vw TO SHARE IN APPLICATION PACKAGE na_prllm_pkg;
```

We can now add the credentials to the `PRLLM_CREDS` table for use by the app.
In the following SQL, replace
* `SNOWFLAKE_URL` with the URL for your Snowflake account (e.g., `https://abc12345.snowflakecomputing.com`)
* `SNOWFLAKE_IDENTIFIER` with your Snowflake account identifier (e.g, `abc12345`)
* `PRLLM_USER` with the username you created above
* `PRLLM_PASSWORD` with the password for the user you created above
* `INGRESS_URL` - take the hostname of ingress URL for your LLM service from above, and prepend with `wss://` instead of `https://`, and add the suffix `/ws` (e.g., `wss://zyxwvuts-abc12345.snowflakecomputing.app/ws`)

```sql
USE ROLE nap_role;
INSERT INTO na_prllm_pkg.shared_data.prllm_creds 
    SELECT  'SNOWFLAKE_URL' AS host, 
            'SNOWFLAKE_IDENTIFIER' AS account, 
            'PRLLM_USER' AS user, 
            'PRLLM_PASSWORD' AS password,
            'INGRESS_URL' AS api_url,
            current_account() AS current_account;
```

This will give access to your current account (the Provider account). We
can enable other accounts by adding the same line, but providing the 
account identifier (as returned by `SELECT current_account()`) for other
Consumer accounts.

Next, we need to upload the Native Applications files. Upload the entire
`na_prllm` directory (not the directory that contains this README, but the
subdirectory with the same name, the one that contains the `v1` subdirectory) 
to the `NAPP.NAPP.APP_STAGE`.

Now we can create the VERSION for the APPLICATION PACKAGE:
```sql
USE ROLE nap_role;
ALTER APPLICATION PACKAGE na_prllm_pkg ADD VERSION v1 USING @napp.napp.app_stage/na_prllm/v1;
```

If you need to make some changes and create a new PATCH for the version, you can run
this instead
```sql
USE ROLE nap_role;
ALTER APPLICATION PACKAGE na_prllm_pkg ADD PATCH FOR VERSION v1 USING @napp.napp.app_stage/na_prllm/v1;
```

### Testing on the Provider Side

#### Setup for Testing on the Provider Side
We can test our Native App on the Provider by mimicking what it would look like on the 
Consumer side (a benefit/feature of the Snowflake Native App Framework).

To do this, we need to create a ROLE, a virtual warehouse, and grant it 
permissions

```sql
USE ROLE ACCOUNTADMIN;
-- (Mock) Consumer role
CREATE ROLE IF NOT EXISTS nac;
GRANT ROLE nac TO ROLE ACCOUNTADMIN;
GRANT CREATE DATABASE ON ACCOUNT TO ROLE nac;
CREATE WAREHOUSE IF NOT EXISTS wh_nac WITH WAREHOUSE_SIZE='XSMALL';
GRANT USAGE ON WAREHOUSE wh_nac TO ROLE nac WITH GRANT OPTION;
GRANT CREATE APPLICATION ON ACCOUNT TO ROLE nac;

USE ROLE nap_role;
GRANT INSTALL, DEVELOP ON APPLICATION PACKAGE na_prllm_pkg TO ROLE nac;
```

#### Testing on the Provider Side
First, let's install the Native App.

Run the following commands:
```sql
USE ROLE nac;
USE WAREHOUSE wh_nac;

DROP APPLICATION IF EXISTS na_prllm_app;
CREATE APPLICATION na_prllm_app FROM APPLICATION PACKAGE na_prllm_pkg USING VERSION v1;

GRANT APPLICATION ROLE na_prllm_app.app_user TO ROLE sandbox;
```

Next we need to configure the Native App. We can do this via Snowsight by
visiting the Apps tab and clicking on our Native App `NA_PRLLM_APP`.
* Click the "Connections" tab
* Click the "Review" button to open the dialog to create the
  necessary `EXTERNAL ACCESS INTEGRATION`. Review the dialog and
  click "Connect".

Unfortunately, there are a few things not working as nicely as 
we'd like in the Native App Framework (but improvements are coming), 
so, for now, we will need to explicitly GRANT usage on the
EXTERNAL ACCESS INTEGRATION and create the functions.

Run the following
```sql
USE ROLE nac;
SHOW REFERENCES IN APPLICATION na_prllm_app;
```

Note the value of `object_name` for the Reference named `EGRESS_EAI_PRLLM`.
Using that value in place of `OBJECT_NAME` in the following command, run
```sql
USE ROLE nac;
GRANT USAGE ON INTEGRATION OBJECT_NAME TO APPLICATION na_prllm_app;
CALL na_prllm_app.config.create_function_prllm_with_eai('OBJECT_NAME');
```
Note that in the first command you put in the value unquoted, but in
the second command you put in the value with single quotes.

And you are now ready to use the `prllm` function:
```sql
SELECT na_prllm.app.app_public.prllm('What is an LLM?');
```

You can grant access to this function to other users and roles
by granting the APPLICATION ROLE `app_user`.

##### Cleanup
To clean up the Native App test install, you can just `DROP` it:

```
DROP APPLICATION na_prllm_app;
```

### Publishing/Sharing your Native App
You Native App is now ready on the Provider Side. You can make the Native App available
for installation in other Snowflake Accounts by setting a default PATCH and Sharing the App
in the Snowsight UI.

Navigate to the "Apps" tab and select "Packages" at the top. Now click on your App Package 
(`NA_PRLLM_PKG`). From here you can click on "Set release default" and choose the latest patch
(the largest number) for version `v1`. 

Next, click "Share app package". This will take you to the Provider Studio. Give the listing
a title, choose "Only Specified Consumers", and click "Next". For "What's in the listing?", 
select the App Package (`NA_PRLLM_PKG`). Add a brief description. Lastly, add the Consumer account
identifier to the "Add consumer accounts". Then click "Publish".

### Using the Native App on the Consumer Side

#### Setup for Testing on the Consumer Side
We're ready to import our Native App in the Consumer account.

To do the setup, run the following commands, which will create the role and
virtual warehouse for the Native App. 
```sql
USE ROLE ACCOUNTADMIN;
-- (Mock) Consumer role
CREATE ROLE IF NOT EXISTS nac;
GRANT ROLE nac TO ROLE ACCOUNTADMIN;
GRANT CREATE DATABASE ON ACCOUNT TO ROLE nac;
CREATE WAREHOUSE IF NOT EXISTS wh_nac WITH WAREHOUSE_SIZE='XSMALL';
GRANT USAGE ON WAREHOUSE wh_nac TO ROLE nac WITH GRANT OPTION;
GRANT CREATE APPLICATION ON ACCOUNT TO ROLE nac;
```

#### Using the Native App on the Consumer
To get the Native app, navigate to the "Apps" sidebar. You should see the app at the top under
"Recently Shared with You". Click the "Get" button. Select a Warehouse to use for installation.
Under "Application name", choose the name `NA_PRLLM_APP` (You _can_ choose a 
different name, but the scripts use `NA_PRLLM_APP`). Click "Get".

Next we need to configure the Native App. We can do this via Snowsight by
Next we need to configure the Native App. We can do this via Snowsight by
visiting the Apps tab and clicking on our Native App `NA_PRLLM_APP`.
* Click the "Connections" tab
* Click the "Review" button to open the dialog to create the
  necessary `EXTERNAL ACCESS INTEGRATION`. Review the dialog and
  click "Connect".

Unfortunately, there are a few things not working as nicely as 
we'd like in the Native App Framework (but improvements are coming), 
so, for now, we will need to explicitly GRANT usage on the
EXTERNAL ACCESS INTEGRATION and create the functions.

Run the following
```sql
USE ROLE nac;
SHOW REFERENCES IN APPLICATION na_prllm_app;
```

Note the value of `object_name` for the Reference named `EGRESS_EAI_PRLLM`.
Using that value in place of `OBJECT_NAME` in the following command, run
```sql
USE ROLE nac;
GRANT USAGE ON INTEGRATION OBJECT_NAME TO APPLICATION na_prllm_app;
CALL na_prllm_app.config.create_function_prllm_with_eai('OBJECT_NAME');
```
Note that in the first command you put in the value unquoted, but in
the second command you put in the value with single quotes.

And you are now ready to use the `prllm` function:
```sql
SELECT na_prllm.app.app_public.prllm('What is an LLM?');
```

You can grant access to this function to other users and roles
by granting the APPLICATION ROLE `app_user`.

##### Cleanup
To clean up the Native App, you can just uninstall it from the "Apps" tab.

