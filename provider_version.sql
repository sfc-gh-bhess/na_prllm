USE ROLE nap_role;

-- Upload files to Stage
ALTER APPLICATION PACKAGE na_prllm_pkg ADD VERSION v1 USING @napp.napp.app_stage/na_prllm/v1;

-- for subsequent updates to version
ALTER APPLICATION PACKAGE na_prllm_pkg ADD PATCH FOR VERSION v1 USING @napp.napp.app_stage/na_prllm/v1;
