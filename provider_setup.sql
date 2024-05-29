USE ROLE ACCOUNTADMIN;
-- Native App
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


-- Provider-Side Service
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
SHOW IMAGE REPOSITORIES;

-- Run ./configure.sh to update files
-- Upload llm.yaml to @spcs.napp.specs
-- Build and push Docker images via Makefile (`make all`)
DROP SERVICE IF EXISTS spcs.napp.llama_2;
CREATE SERVICE spcs.napp.llama_2
    IN COMPUTE POOL gpu_nv_s
    FROM @spcs.napp.specs
    SPECIFICATION_FILE='llm.yaml'
    EXTERNAL_ACCESS_INTEGRATIONS = ( HF_ACCESS_INTEGRATION );

GRANT USAGE ON SERVICE spcs.napp.llama TO ROLE prllm;