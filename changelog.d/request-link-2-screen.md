### Added
- **Request Link** (Settings, and the Pipeline): a link of your own that anyone can open to ask you for service, from any phone or computer, without the app. Copy it, share it, text it to someone, or show it as a QR code to scan, save or print for a flyer or your truck. Choose which of your services the form offers (up to 12, from your Service Catalog; a service you remove from the catalog leaves the form too) and a welcome line. With no catalog yet, a general list is offered with nothing ticked, so a form never offers a service you don't do. The request comes to your phone as a text from the person's own phone. If your Business Profile has no name or phone yet, the screen says which to add.

### Internal
- New iCloud fields: `BusinessProfile.requestServices`, `requestServicesChosen`, `requestWelcome` (deploy the schema before the next release). The QR code drawing is shared with the payment QR code on PDFs (`QRCode`).
