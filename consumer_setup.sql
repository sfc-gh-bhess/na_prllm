USE ROLE ACCOUNTADMIN;
-- (Mock) Consumer role
CREATE ROLE IF NOT EXISTS nac;
GRANT ROLE nac TO ROLE ACCOUNTADMIN;
GRANT CREATE DATABASE ON ACCOUNT TO ROLE nac;
CREATE WAREHOUSE IF NOT EXISTS wh_nac WITH WAREHOUSE_SIZE='XSMALL';
GRANT USAGE ON WAREHOUSE wh_nac TO ROLE nac WITH GRANT OPTION;
