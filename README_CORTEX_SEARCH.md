md
# 📄 Snowflake Document AI + Cortex Search Quickstart

A complete, end‑to‑end workflow demonstrating how to:

- Ingest PDF documents  
- Parse and extract structured fields using **Document AI**  
- Automate processing with **Streams + Tasks**  
- Flatten results into analytics‑ready tables  
- Add **Cortex Search** for semantic retrieval  
- Optionally combine search + LLMs for RAG‑style querying  

This quickstart is designed to run top‑to‑bottom in a single Snowflake worksheet.

---

## 🚀 What This Quickstart Builds

### **1. Environment Setup**
Creates all required Snowflake objects:

- Warehouse: `doc_ai_wh`  
- Database + schema: `doc_ai_db.doc_schema`  
- Privileges for Document AI + Cortex  
- Permissions for Streams + Tasks  

---

### **2. Document Staging**
Creates an internal stage with directory tracking:

my_docs_stage

Code

Upload PDFs via Snowsight:

> **Snowsight → Data → Databases → doc_ai_db → doc_schema → my_docs_stage → Upload Files**

---

### **3. Parsing Documents**
Uses `AI_PARSE_DOCUMENT` to extract:

- Full text  
- Layout  
- Page structure  

Results are stored in a raw table.

---

### **4. Structured Extraction**
Uses `AI_EXTRACT` to pull out key invoice fields:

- Invoice number  
- Vendor name  
- Invoice date  
- Total amount  

---

### **5. Batch Processing**
Processes all staged files and stores results in:

invoices_raw

Code

---

### **6. Flattening**
Creates a clean, analytics‑ready table:

invoices_flat

Code

This table powers both SQL queries and Cortex Search.

---

### **7. Automation**
Sets up:

- A **stream** to detect new files  
- A **task** that automatically extracts fields every 5 minutes  

This enables continuous ingestion.

---

## 🔍 8. Adding Cortex Search

Cortex Search provides semantic search across both structured invoice fields and full parsed text.

---

### **8.1 Create the Cortex Search Service**

```sql
USE DATABASE doc_ai_db;
USE SCHEMA doc_schema;

CREATE OR REPLACE SEARCH SERVICE invoices_search_service
  ON invoices_flat
  WAREHOUSE = doc_ai_wh
  TARGET_LAG = '5 minutes'
  INDEXES = (
    {
      name: 'invoices_index',
      columns: ['vendor_name', 'invoice_number', 'full_text']
    }
  );
8.2 Automate Index Refreshing
sql
CREATE OR REPLACE TASK refresh_invoices_search_index
  WAREHOUSE = doc_ai_wh
  SCHEDULE = '5 MINUTE'
AS
  ALTER SEARCH SERVICE invoices_search_service REFRESH;
Enable it:

sql
ALTER TASK refresh_invoices_search_index RESUME;
8.3 Semantic Search Examples
Search by vendor (semantic, not exact match)
sql
SELECT *
FROM SEARCH(invoices_search_service, 'invoices_index')
WHERE MATCH('invoices from ACME Corporation');
Search by concept
sql
SELECT vendor_name, invoice_number, total_amount
FROM SEARCH(invoices_search_service, 'invoices_index')
WHERE MATCH('late payment fees or overdue charges');
Search by amount + date
sql
SELECT *
FROM SEARCH(invoices_search_service, 'invoices_index')
WHERE MATCH('invoices over $10,000 from January');
Search inside full parsed text
sql
SELECT invoice_number, vendor_name
FROM SEARCH(invoices_search_service, 'invoices_index')
WHERE MATCH('cloud hosting services');
🤖 9. Optional: Cortex LLM + Search (RAG)
Combine semantic retrieval with LLM summarization:

sql
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large',
  CONCAT(
    'Summarize the invoice details for this document: ',
    full_text
  )
)
FROM SEARCH(invoices_search_service, 'invoices_index')
WHERE MATCH('invoice for software subscription renewal');
This produces a natural‑language summary of the retrieved invoice.

🧠 How to Use This Quickstart
Open Snowflake Snowsight

Create a new worksheet

Paste the contents of document_ai_quickstart.sql

Run the script top‑to‑bottom

Upload your invoice PDFs into my_docs_stage

Query invoices_flat or use the Cortex Search examples

📌 Requirements
Snowflake account with Cortex AI + Document AI enabled

Ability to assume ACCOUNTADMIN and SYSADMIN roles

PDF documents (sample invoices included)

📦 Suggested Project Structure
Code
/document-ai-cortex-quickstart
  ├── document_ai_quickstart.sql
  ├── cortex_search_extension.sql
  ├── README.md
  └── sample_invoices/
📝 License
This project is licensed under the MIT License.

Code

---

If you want, I can also generate:

- A version with **badges** (Snowflake, SQL, MIT, etc.)  
- A **more enterprise‑formal** version  
- A **more playful developer‑friendly** version  
- A **combined SQL script** that includes Cortex Search inline  

Just tell me the vibe you want.
