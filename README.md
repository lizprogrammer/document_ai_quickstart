## 🚀 What This Quickstart Demonstrates

### **1. Environment Setup**
Creates:
- Warehouse (`doc_ai_wh`)
- Database + schema (`doc_ai_db.doc_schema`)
- Required privileges for Document AI + Cortex
- Permissions for Streams + Tasks

### **2. Document Staging**
Creates an internal stage (`my_docs_stage`) with directory tracking enabled.

**Upload PDFs using the Snowflake UI:**
> Snowsight → Data → Databases → doc_ai_db → doc_schema → my_docs_stage → **Upload Files**

### **3. Parsing Documents**
Uses `AI_PARSE_DOCUMENT` to extract full text + layout from PDFs.

### **4. Structured Extraction**
Uses `AI_EXTRACT` to pull out:
- Invoice number  
- Vendor name  
- Invoice date  
- Total amount  

### **5. Batch Processing**
Processes all files in the stage and stores results in `invoices_raw`.

### **6. Flattening**
Creates a clean, query‑ready table `invoices_flat`.

### **7. Automation**
Sets up:
- A **stream** to detect new files  
- A **task** that automatically extracts fields from new documents every 5 minutes  

### **8. Querying With Cortex**
Examples include:
- Asking questions about structured invoice fields  
- Asking questions about the full parsed document text  
- Filtering by vendor, date, or invoice number  

---

## 🧠 How to Use This Quickstart

1. Open Snowflake Snowsight.
2. Create a new worksheet.
3. Paste the contents of `document_ai_quickstart.sql`.
4. Run the script top‑to‑bottom.
5. Upload your invoice PDFs into `my_docs_stage`.
6. Query `invoices_flat` or use the Cortex examples to ask natural‑language questions.

---

## 📌 Requirements

- Snowflake account with **Cortex AI** + **Document AI** enabled  
- Ability to assume `ACCOUNTADMIN` and `SYSADMIN` roles  
- PDF documents (sample invoices included)

---

## 📝 License

This project is licensed under the MIT License.
