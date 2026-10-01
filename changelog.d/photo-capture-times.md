### Added
- Job photos keep when they were taken, and where that time came from. A photo taken with PlowR's camera keeps the shutter time the camera recorded (not when Use Photo was tapped). One picked from the library keeps the date stored in its file, with its time zone when the file has one. The Service Report says which, under each photo: "Before, taken 4:55 AM" for PlowR's camera, "file dated 4:55 AM" for a library photo (a date that can be changed), with "(zone assumed)" when the file gave no zone. When a photo isn't from the visit's day, its date and year are shown too, so a photo from another storm or another winter can't pass as this visit's. The client's photos show the same: Taken, File Dated, or Added, and they're sorted by it.

### Fixed
- A photo's time was the moment Record Services was saved, not when it was taken: a "before" photo read as taken after the work, and every photo from one stop shared a time. Photos saved before this have no known capture time; the Service Report shows none for them, and the app shows when they were added. A visit's photos are in the same order in the app and the report.

### Internal
- New CloudKit fields to deploy: `CD_StopPhoto.capturedAt`, `CD_StopPhoto.captureSourceRaw` (run Set Up iCloud Schema from a debug build, then deploy).
