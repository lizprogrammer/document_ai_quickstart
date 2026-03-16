--------------------------------------------------------------------------------
-- Snowflake Smart Document Platform Quickstart
-- Supports BOTH:
--   (A) Search-only from S3 via Cortex Search
--   (B) Parse + Extract + Flatten via Document AI
--------------------------------------------------------------------------------


===============================
= 1. GLOBAL SETUP
===============================

USE ROLE ACCOUNTADMIN;

-- Warehouse
CREATE OR REPLACE WAREHOUSE doc_ai_wh
  WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

-- Database + schema
CREATE DATABASE IF NOT EXISTS doc_ai_db;
CREATE SCHEMA  IF NOT EXISTS doc_ai_db.doc_schema;

-- Cortex AI permissions
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE SYSADMIN;

-- Privileges
GRANT USAGE ON DATABASE doc_ai_db TO ROLE SYSADMIN;
GRANT USAGE ON SCHEMA  doc_ai_db.doc_schema TO ROLE SYSADMIN;
GRANT CREATE TABLE ON SCHEMA doc_ai_db.doc_schema TO ROLE SYSADMIN;
GRANT CREATE STAGE ON SCHEMA doc_ai_db.doc_schema TO ROLE SYSADMIN;
GRANT CREATE STREAM ON SCHEMA doc_ai_db.doc_schema TO ROLE SYSADMIN;
GRANT CREATE TASK   ON SCHEMA doc_ai_db.doc_schema TO ROLE SYSADMIN;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE SYSADMIN;

USE ROLE SYSADMIN;
USE WAREHOUSE doc_ai_wh;
USE DATABASE doc_ai_db;
USE SCHEMA doc_schema;



================================================================================
= 2. PATH A — SEARCH-ONLY (EXTERNAL S3 STAGE + CORTEX SEARCH)
================================================================================

--------------------------------
-- 2.1 Create external S3 stage
--------------------------------
-- Replace with your bucket + IAM role or keypair
CREATE OR REPLACE STAGE raw_docs_ext_stage
  URL='s3://YOUR_BUCKET_NAME/DOCUMENTS/'
  CREDENTIALS = (AWS_ROLE = 'arn:aws:iam::123456789012:role/YourSnowflakeRole')
  DIRECTORY = (ENABLE = TRUE);

LIST @raw_docs_ext_stage;


--------------------------------
-- 2.2 Create Cortex Search index
--------------------------------
CREATE OR REPLACE CORTEX SEARCH SERVICE raw_docs_search
  ON STAGE raw_docs_ext_stage
  WAREHOUSE = doc_ai_wh;


--------------------------------
-- 2.3 Query documents using natural language
--------------------------------
SELECT SNOWFLAKE.CORTEX.SEARCH(
  'raw_docs_search',
  'Find documents related to license renewals'
);



================================================================================
= 3. PATH B — PARSE + EXTRACT + FLATTEN (INTERNAL STAGE)
================================================================================

--------------------------------
-- 3.1 Create internal stage
--------------------------------
CREATE OR REPLACE STAGE my_docs_stage
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- Upload PDFs via Snowsight UI
ALTER STAGE my_docs_stage REFRESH;
LIST @my_docs_stage;


--------------------------------
-- 3.2 Parse a single document
--------------------------------
SELECT AI_PARSE_DOCUMENT(
  TO_FILE('@my_docs_stage', 'invoice.pdf'),
  {'mode': 'LAYOUT'}
) AS parsed_doc;


--------------------------------
-- 3.3 Extract structured fields
--------------------------------
SELECT AI_EXTRACT(
  TO_FILE('@my_docs_stage', 'invoice.pdf'),
  {
    'invoice_number': 'What is the invoice number?',
    'vendor_name':    'What is the name of the vendor?',
    'invoice_date':   'What is the invoice date?',
    'total_amount':   'What is the total amount due?'
  }
) AS extracted;


--------------------------------
-- 3.4 Batch extract all documents
--------------------------------
CREATE OR REPLACE TABLE invoices_raw AS
SELECT
  RELATIVE_PATH AS filename,
  AI_EXTRACT(
    TO_FILE('@my_docs_stage', RELATIVE_PATH),
    {
      'invoice_number': 'What is the invoice number?',
      'vendor_name':    'What is the name of the vendor?',
      'invoice_date':   'What is the invoice date?',
      'total_amount':   'What is the total amount due?'
    }
  ) AS result
FROM DIRECTORY(@my_docs_stage);


--------------------------------
-- 3.5 Flatten into clean table
--------------------------------
CREATE OR REPLACE TABLE invoices_flat AS
SELECT
  filename,
  result:response:invoice_number::STRING AS invoice_number,
  result:response:vendor_name::STRING    AS vendor_name,
  result:response:invoice_date::STRING   AS invoice_date,
  result:response:total_amount::STRING   AS total_amount
FROM invoices_raw;

SELECT * FROM invoices_flat;



================================================================================
= 4. AUTOMATION (STREAM + TASK)
================================================================================

--------------------------------
-- 4.1 Detect new files
--------------------------------
CREATE OR REPLACE STREAM docs_stream ON STAGE my_docs_stage;


--------------------------------
-- 4.2 Task to process new files
--------------------------------
CREATE OR REPLACE TASK process_new_docs
  WAREHOUSE = doc_ai_wh
  SCHEDULE  = '5 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('docs_stream')
AS
  INSERT INTO invoices_raw
  SELECT
    RELATIVE_PATH,
    AI_EXTRACT(
      TO_FILE('@my_docs_stage', RELATIVE_PATH),
      {
        'invoice_number': 'What is the invoice number?',
        'vendor_name':    'What is the vendor name?',
        'invoice_date':   'What is the invoice date?',
        'total_amount':   'What is the total amount due?'
      }
    )
  FROM docs_stream
  WHERE METADATA$ACTION = 'INSERT';

ALTER TASK process_new_docs RESUME;



================================================================================
= 5. QUERYING WITH CORTEX AI
================================================================================

--------------------------------
-- 5.1 Ask questions about structured fields
--------------------------------
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'Here is an invoice record:' ||
  '\nFilename: '       || FILENAME ||
  '\nInvoice Number: ' || INVOICE_NUMBER ||
  '\nVendor: '         || VENDOR_NAME ||
  '\nInvoice Date: '   || INVOICE_DATE ||
  '\nTotal Amount: '   || TOTAL_AMOUNT ||
  '\n\nAnswer this question: What is the invoice number?'
) AS answer
FROM invoices_flat;


--------------------------------
-- 5.2 Ask questions using full parsed text
--------------------------------
SET question = 'What is the invoice number?';

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  CONCAT(
    'Here is the full text of an invoice document:\n\n',
    TO_VARCHAR(AI_PARSE_DOCUMENT(TO_FILE('@my_docs_stage', FILENAME), {'mode': 'LAYOUT'})),
    '\n\nAnswer this question: ',
    $question
  )
) AS answer
FROM invoices_flat;


--------------------------------
-- 5.3 Filter by vendor/date/invoice number
--------------------------------
SET filter_field = 'vendor_name';
SET filter_value = 'NovaTech Solutions, Inc.';

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  CONCAT(
    'Here is the full text of an invoice document:\n\n',
    TO_VARCHAR(AI_PARSE_DOCUMENT(TO_FILE('@my_docs_stage', FILENAME), {'mode': 'LAYOUT'})),
    '\n\nAnswer this question: ',
    $question
  )
) AS answer
FROM invoices_flat
WHERE IDENTIFIER($filter_field) = $filter_value;


--------------------------------------------------------------------------------
-- END OF COMBINED QUICKSTART
--------------------------------------------------------------------------------
