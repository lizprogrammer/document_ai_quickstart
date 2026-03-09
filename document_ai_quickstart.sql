--------------------------------------------------------------------------------
-- Snowflake Document AI Quickstart
-- End‑to‑end pipeline: ingest → parse → extract → flatten → automate → query
--------------------------------------------------------------------------------


-------------------------------
-- 1. SETUP
-------------------------------

USE ROLE ACCOUNTADMIN;

-- Warehouse for Document AI
CREATE OR REPLACE WAREHOUSE doc_ai_wh
  WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

-- Database + schema
CREATE DATABASE IF NOT EXISTS doc_ai_db;
CREATE SCHEMA  IF NOT EXISTS doc_ai_db.doc_schema;

-- Allow SYSADMIN to use Cortex AI functions
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE SYSADMIN;

-- Privileges for SYSADMIN
GRANT USAGE ON DATABASE doc_ai_db TO ROLE SYSADMIN;
GRANT USAGE ON SCHEMA   doc_ai_db.doc_schema TO ROLE SYSADMIN;
GRANT CREATE TABLE ON SCHEMA doc_ai_db.doc_schema TO ROLE SYSADMIN;
GRANT CREATE STAGE ON SCHEMA doc_ai_db.doc_schema TO ROLE SYSADMIN;

-- Streams + tasks
GRANT CREATE STREAM ON SCHEMA doc_ai_db.doc_schema TO ROLE SYSADMIN;
GRANT CREATE TASK   ON SCHEMA doc_ai_db.doc_schema TO ROLE SYSADMIN;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE SYSADMIN;

-- Switch to working role
USE ROLE SYSADMIN;
USE WAREHOUSE doc_ai_wh;
USE DATABASE doc_ai_db;
USE SCHEMA doc_schema;



-------------------------------
-- 2. STAGE DOCUMENTS
-------------------------------

-- Create internal stage
CREATE OR REPLACE STAGE my_docs_stage
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- Upload PDFs using Snowsight UI:
-- Data → Databases → doc_ai_db → doc_schema → my_docs_stage → Upload Files

-- Refresh directory after upload
ALTER STAGE my_docs_stage REFRESH;
LIST @my_docs_stage;



-------------------------------
-- 3. PARSE DOCUMENTS
-------------------------------

SELECT AI_PARSE_DOCUMENT(
  TO_FILE('@my_docs_stage', 'invoice.pdf'),
  {'mode': 'LAYOUT'}
) AS parsed_doc;



-------------------------------
-- 4. EXTRACT STRUCTURED FIELDS
-------------------------------

SELECT AI_EXTRACT(
  TO_FILE('@my_docs_stage', 'invoice.pdf'),
  {
    'invoice_number': 'What is the invoice number?',
    'vendor_name':    'What is the name of the vendor?',
    'invoice_date':   'What is the invoice date?',
    'total_amount':   'What is the total amount due?'
  }
) AS extracted;



-------------------------------
-- 5. BATCH PROCESS ALL FILES
-------------------------------

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



-------------------------------
-- 6. FLATTEN INTO CLEAN TABLE
-------------------------------

CREATE OR REPLACE TABLE invoices_flat AS
SELECT
  filename,
  result:response:invoice_number::STRING AS invoice_number,
  result:response:vendor_name::STRING    AS vendor_name,
  result:response:invoice_date::STRING   AS invoice_date,
  result:response:total_amount::STRING   AS total_amount
FROM invoices_raw;

SELECT * FROM invoices_flat;



-------------------------------
-- 7. AUTOMATE WITH STREAMS + TASKS
-------------------------------

-- Detect new files
CREATE OR REPLACE STREAM docs_stream ON STAGE my_docs_stage;

-- Process new files every 5 minutes
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



-------------------------------
-- 8. QUERY WITH CORTEX AI
-------------------------------

-- Ask a question using flattened fields
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

-- Ask a question using full parsed text
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

-- Filter by vendor/date/invoice number
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
-- END OF QUICKSTART
--------------------------------------------------------------------------------
