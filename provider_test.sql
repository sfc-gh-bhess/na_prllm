-- FOLLOW THE consumer_setup.sql TO SET UP THE TEST ON THE PROVIDER
-- For Provider-side Testing
USE ROLE nap_role;
GRANT INSTALL, DEVELOP ON APPLICATION PACKAGE na_prllm_pkg TO ROLE nac;
USE ROLE ACCOUNTADMIN;
GRANT CREATE APPLICATION ON ACCOUNT TO ROLE nac;


-- Create the APPLICATION
USE ROLE nac;
USE WAREHOUSE wh_nac;

DROP APPLICATION IF EXISTS na_prllm_app;
CREATE APPLICATION na_prllm_app FROM APPLICATION PACKAGE na_prllm_pkg USING VERSION v1;

GRANT APPLICATION ROLE na_prllm_app.app_user TO ROLE sandbox;

SELECT na_prllm_app.app_public.prllm('What is an LLM?');


-- Use this for development purposes (after GRANTing NAC access to the STAGE and IMAGE REPOSITORY)
-- This is currently broken (SNOW-1435359)
USE ROLE nac;
DROP APPLICATION na_prllm_app;
CREATE APPLICATION na_prllm_app FROM APPLICATION PACKAGE na_prllm_pkg USING '@napp.napp.app_stage/na_prllm/v1';

