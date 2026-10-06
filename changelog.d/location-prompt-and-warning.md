### Changed
- The first location prompt (While Using the App) now also says PlowR records when you arrive at and leave a stop during a route. iOS shows that prompt before the "Always" one, which already said so; a permission prompt has to name every use before App Review.

### Internal
- Removed an unused `colorPDFs` variable from the business report PDF (a compiler warning): its accent colour already follows the colour-PDFs setting through `PDFGenerator.accent(for:)`.
