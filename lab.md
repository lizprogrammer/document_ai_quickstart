# Snowflake Document AI Quickstart (Workshop Edition)

A fast, end‑to‑end lab to get hands‑on with Snowflake Document AI and Cortex.  
You will: stage documents → parse → extract → batch → flatten → automate → query.

---

## 1. Setup

Run the following to create your environment:

```sql
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE WAREHOUSE doc_ai_wh
  WAREHOUSE_SIZE = 'X-SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

CREATE DATABASE IF NOT EXISTS doc_ai_db;
CREATE SCHEMA  IF NOT EXISTS doc_ai_db.doc_schema;

GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE SYSADMIN;

GRANT USAGE, CREATE TABLE, CREATE STAGE ON SCHEMA doc_ai_db.doc_schema TO ROLE SYSADMIN;
GRANT CREATE STREAM, CREATE TASK ON SCHEMA doc_ai_db.doc_schema TO ROLE SYSADMIN;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE SYSADMIN;

USE ROLE SYSADMIN;
USE WAREHOUSE doc_ai_wh;
USE DATABASE doc_ai_db;
USE SCHEMA doc_schema;
2. Stage Your Documents
Create a stage:

sql
CREATE OR REPLACE STAGE my_docs_stage
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');
Upload PDFs in Snowsight:
Data → doc_ai_db → doc_schema → my_docs_stage → Upload Files

Refresh and list:

sql
ALTER STAGE my_docs_stage REFRESH;
LIST @my_docs_stage;
3. Parse One Document
Replace with a filename from your stage:

sql
SELECT AI_PARSE_DOCUMENT(
  TO_FILE('@my_docs_stage', 'invoice1.pdf'),
  {'mode': 'LAYOUT'}
) AS parsed_doc;
4. Extract Structured Fields
sql
SELECT AI_EXTRACT(
  TO_FILE('@my_docs_stage', 'invoice1.pdf'),
  {
    'invoice_number': 'What is the invoice number?',
    'vendor_name':    'What is the name of the vendor?',
    'invoice_date':   'What is the invoice date?',
    'total_amount':   'What is the total amount due?'
  }
) AS extracted;
5. Batch Process All Files
sql
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
Preview:

sql
SELECT * FROM invoices_raw;
6. Flatten Into a Clean Table
sql
CREATE OR REPLACE TABLE invoices_flat AS
SELECT
  filename,
  result:response:invoice_number::STRING AS invoice_number,
  result:response:vendor_name::STRING    AS vendor_name,
  result:response:invoice_date::STRING   AS invoice_date,
  result:response:total_amount::STRING   AS total_amount
FROM invoices_raw;
sql
SELECT * FROM invoices_flat;
7. Automate New Files (Streams + Tasks)
Create a stream:

sql
CREATE OR REPLACE STREAM docs_stream ON STAGE my_docs_stage;
Create a task:

sql
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
Resume:

sql
ALTER TASK process_new_docs RESUME;
Upload a new PDF and verify:

sql
SELECT * FROM invoices_flat ORDER BY filename DESC;
8. Query With Cortex AI
Ask about extracted fields
sql
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'Invoice details:' ||
  '\nFilename: '       || filename ||
  '\nInvoice Number: ' || invoice_number ||
  '\nVendor: '         || vendor_name ||
  '\nInvoice Date: '   || invoice_date ||
  '\nTotal Amount: '   || total_amount ||
  '\n\nWhat is the invoice number?'
) AS answer
FROM invoices_flat;
Ask using full parsed text
sql
SET question = 'What is the invoice number?';

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  CONCAT(
    'Full invoice text:\n\n',
    TO_VARCHAR(AI_PARSE_DOCUMENT(TO_FILE('@my_docs_stage', filename), {'mode': 'LAYOUT'})),
    '\n\nQuestion: ',
    $question
  )
) AS answer
FROM invoices_flat;
Optional Cleanup
sql
ALTER TASK process_new_docs SUSPEND;
DROP TASK process_new_docs;
DROP STREAM docs_stream;
DROP STAGE my_docs_stage;
DROP TABLE invoices_flat;
DROP TABLE invoices_raw;
DROP SCHEMA doc_ai_db.doc_schema;
DROP DATABASE doc_ai_db;
DROP WAREHOUSE 
