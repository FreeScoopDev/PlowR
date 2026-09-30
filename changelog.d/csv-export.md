### Added
- **Export Data** (Settings): your clients, invoices and Service History as spreadsheet (CSV) files, to save to Files, send to an accountant, or bring into accounting software. They open in Numbers, Excel and Google Sheets. Money has two decimals and dates are year-month-day, so a spreadsheet reads them as numbers and dates. Text that a spreadsheet would treat as a formula (a note starting with "=") is kept as text.

### Internal
- `CSVExport` writes the files: RFC 4180 quoting, CRLF line endings, a byte-order mark so Excel reads accents, and a leading apostrophe on text starting with = + - @ so it can't run as a formula. Delete Account & Data removes exported files with the shared PDFs (the step is now "shared files").
