### Changed
- The first location prompt (While Using the App) now names every use of location: the map, arrival estimates, adding your location to a text when you choose to, noticing when you arrive at and leave a stop during a route (to record those times and offer to text the next client), and local weather. iOS shows that prompt before the "Always" one, and App Review expects a permission prompt to describe each use; it named neither the arrival and departure times nor the location in texts.

### Internal
- Removed an unused `colorPDFs` variable from the business report PDF (a compiler warning): its accent colour already follows the colour-PDFs setting through `PDFGenerator.accent(for:)`.
