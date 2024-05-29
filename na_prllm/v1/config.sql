CREATE OR ALTER VERSIONED SCHEMA config;
GRANT USAGE ON SCHEMA config TO APPLICATION ROLE app_admin;

-- CALLBACKS
CREATE PROCEDURE config.reference_callback(ref_name STRING, operation STRING, ref_or_alias STRING)
 RETURNS STRING
 LANGUAGE SQL
 AS $$
    DECLARE
        retstr STRING;
    BEGIN
        SYSTEM$LOG_INFO('NA_PRLLM: reference_callback: ref_name=' || ref_name || ' operation=' || operation);
        CASE (operation)
            WHEN 'ADD' THEN
                SELECT system$set_reference(:ref_name, :ref_or_alias);
                CASE (ref_name)
                    WHEN 'EGRESS_EAI_PRLLM' THEN
                        CALL config.create_function_prllm();
                END;
                retstr := 'Reference set';
            WHEN 'REMOVE' THEN
                SELECT system$remove_reference(:ref_name);
                CASE (ref_name)
                    WHEN 'EGRESS_EAI_PRLLM' THEN
                        CALL config.drop_function_prllm();
                END;
                retstr := 'Reference removed';
            WHEN 'CLEAR' THEN
                SELECT system$remove_reference(:ref_name);
                CASE (ref_name)
                    WHEN 'EGRESS_EAI_PRLLM' THEN
                        CALL config.drop_function_prllm();
                END;
                retstr := 'Reference cleared';
            ELSE
                retstr := 'Unknown operation: ' || operation;
        END;
        RETURN retstr;
    END
    $$;
    GRANT USAGE ON PROCEDURE config.reference_callback(STRING,  STRING,  STRING) TO APPLICATION ROLE app_admin;

CREATE PROCEDURE config.configuration_callback(ref_name STRING)
    RETURNS string
    LANGUAGE SQL
    AS $$
    BEGIN
        CASE (ref_name)
            WHEN 'EGRESS_EAI_PRLLM' THEN
                -- Add EXTERNAL ACCESS INTEGRATION for upload.wikimedia.org
                RETURN '{"type": "CONFIGURATION", "payload": { "host_ports": ["gl5qobgv-sfsenorthamerica-bmh-prod3.snowflakecomputing.app", "tmb98077.snowflakecomputing.com"], "allowed_secrets": "NONE" } }';
        END;
        RETURN '{"type": "ERROR", "payload": "Unknown Reference"}';
    END
    $$;
    GRANT USAGE ON PROCEDURE config.configuration_callback(STRING) TO APPLICATION ROLE app_admin;

-- Checks to see if the list of permissions and references have been set/granted.
CREATE OR REPLACE PROCEDURE config.permissions_and_references(perms ARRAY, refs ARRAY)
    RETURNS boolean
    LANGUAGE sql
    AS $$
    DECLARE
        i INTEGER;
        len INTEGER;
    BEGIN
        FOR i IN 0 TO ARRAY_SIZE(perms)-1 DO
            LET p VARCHAR := GET(perms, i)::VARCHAR;
            IF (NOT SYSTEM$HOLD_PRIVILEGE_ON_ACCOUNT(:p)) THEN
                RETURN false;
            END IF;
        END FOR;

        FOR i IN 0 TO ARRAY_SIZE(refs)-1 DO
            LET p VARCHAR := GET(refs, i)::VARCHAR;
            SELECT ARRAY_SIZE(PARSE_JSON(SYSTEM$GET_ALL_REFERENCES(:p))) INTO :len;
            IF (len < 1) THEN
                RETURN false;
            END IF;
        END FOR;

        RETURN true;
    END
    $$;

CREATE OR REPLACE PROCEDURE config.create_function_prllm()
    RETURNS boolean
    LANGUAGE sql
    AS $$
    DECLARE
        b BOOLEAN;
    BEGIN

        SYSTEM$LOG_INFO('NA_PRLLM: create_function_prllm: For now... just returning');
        RETURN false;



        SYSTEM$LOG_INFO('NA_PRLLM: create_function_prllm: starting');
        -- Check that EGRESS_EAI_PRLLM reference has been set
        SYSTEM$LOG_INFO('NA_PRLLM: create_function_prllm: checking if we have all permissions and references');
        CALL config.permissions_and_references(ARRAY_CONSTRUCT(), ARRAY_CONSTRUCT('EGRESS_EAI_PRLLM')) INTO :b;
        IF (NOT b) THEN
            SYSTEM$LOG_INFO('NA_PRLLM: create_function_prllm: Insufficient permissions');
            RETURN false;
        END IF;

        EXECUTE IMMEDIATE '
        CREATE FUNCTION IF NOT EXISTS app_public.prllm_internal(prompt STRING, host STRING, account STRING, user STRING, password STRING, api_url STRING)
            RETURNS STRING
            LANGUAGE PYTHON
            RUNTIME_VERSION = ''3.10''
            PACKAGES = (''requests'')
            HANDLER = ''prllm.prllm''
            IMPORTS = ( ''/prllm.py'' )
            EXTERNAL_ACCESS_INTEGRATIONS = ( Reference(''EGRESS_EAI_PRLLM'') )'
        ;

        CREATE FUNCTION IF NOT EXISTS app_public.prllm(prompt STRING) 
            RETURNS STRING
            AS 'SELECT app_public.prllm_internal(prompt, host, account, user, password, api_url) FROM shared_data.prllm_creds_vw WHERE current_account = current_account()';
            ;
        GRANT USAGE ON FUNCTION app_public.prllm(STRING) TO APPLICATION ROLE app_user;

        SYSTEM$LOG_INFO('NA_PRLLM: create_function_prllm: finished!');
        RETURN true;
    EXCEPTION WHEN OTHER THEN
        SYSTEM$LOG_INFO('NA_PRLLM: create_function_prllm: ERROR: ' || SQLERRM);
        RETURN false;
    END
    $$;
    -- GRANT USAGE ON PROCEDURE config.create_function_prllm() TO APPLICATION ROLE app_admin;

CREATE OR REPLACE PROCEDURE config.drop_function_prllm()
    RETURNS boolean
    LANGUAGE sql
    AS $$
    BEGIN
        SYSTEM$LOG_INFO('NA_PRLLM: drop_function_prllm: dropping service ST_SPCS');

        DROP FUNCTION IF EXISTS app_public.prllm(STRING, STRING, STRING, STRING, STRING, STRING);
        DROP FUNCTION IF EXISTS app_public.prllm(STRING);
        RETURN true;
    EXCEPTION WHEN OTHER THEN
        SYSTEM$LOG_INFO('NA_PRLLM: drop_function_prllm: ERROR: ' || SQLERRM);
        RETURN false;
    END
    $$;
    -- GRANT USAGE ON PROCEDURE config.drop_function_prllm() TO APPLICATION ROLE app_admin;





CREATE OR REPLACE PROCEDURE config.create_function_prllm_with_eai(eai STRING)
    RETURNS boolean
    LANGUAGE sql
    AS $$
    DECLARE
        b BOOLEAN;
    BEGIN
        SYSTEM$LOG_INFO('NA_PRLLM: create_function_prllm_with_eai: starting');

        DROP FUNCTION IF EXISTS app_public.prllm_internal(STRING, STRING, STRING, STRING, STRING, STRING);
        EXECUTE IMMEDIATE '
        CREATE FUNCTION IF NOT EXISTS app_public.prllm_internal(prompt STRING, host STRING, account STRING, user STRING, password STRING, api_url STRING)
            RETURNS STRING
            LANGUAGE PYTHON
            RUNTIME_VERSION = ''3.10''
            PACKAGES = (''requests'')
            HANDLER = ''prllm.prllm''
            IMPORTS = ( ''/prllm.py'' )
            EXTERNAL_ACCESS_INTEGRATIONS = ( ' || UPPER(eai) || ' )'
        ;

        EXECUTE IMMEDIATE '
        CREATE FUNCTION IF NOT EXISTS app_public.prllm(prompt STRING) 
            RETURNS STRING
            AS ''SELECT app_public.prllm_internal(prompt, host, account, user, password, api_url) FROM shared_data.prllm_creds_vw WHERE current_account = current_account()'''
            ;
        GRANT USAGE ON FUNCTION app_public.prllm(STRING) TO APPLICATION ROLE app_user;

        SYSTEM$LOG_INFO('NA_PRLLM: create_function_prllm_with_eai: finished!');
        RETURN true;
    EXCEPTION WHEN OTHER THEN
        SYSTEM$LOG_INFO('NA_PRLLM: create_function_prllm_with_eai: ERROR: ' || SQLERRM);
        RETURN false;
    END
    $$;
    GRANT USAGE ON PROCEDURE config.create_function_prllm_with_eai(STRING) TO APPLICATION ROLE app_admin;


