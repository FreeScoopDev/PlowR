import Foundation
import ImageIO
import UIKit

/// Where a photo's time came from, which the Service Report says: PlowR's
/// camera took it then, or a library photo's file says so (a date anyone
/// can change), and whether that file gave its time zone.
enum CaptureSource: String {
    /// PlowR's camera, at the shutter (the camera's own metadata).
    case camera
    /// A library photo's file, with its offset from UTC.
    case file
    /// A library photo's file without an offset: read in the phone's zone.
    case fileAssumedZone
}

/// A photo with when it was taken, as Record Services and the client's
/// gallery hold it until it's saved.
struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    /// When it was taken; nil when that isn't known.
    let capturedAt: Date?
    let source: CaptureSource?
}

/// When a job photo was taken. PlowR used to stamp every photo with the
/// time Record Services was saved, so a "before" photo read as taken after
/// the work, and a library photo from another day as taken that day. Now:
/// a camera photo carries the shutter time the camera wrote; a library
/// photo, the time in its file. A photo whose time isn't known keeps none:
/// the Service Report doesn't guess.
enum PhotoCapture {
    /// The time in a photo's EXIF properties ("{Exif}": DateTimeOriginal,
    /// and OffsetTimeOriginal when the camera wrote it), and whether it had
    /// its zone. Without one, read in `timeZone` (the phone's).
    static func captureTime(exif: [String: Any]?, timeZone: TimeZone = .current) -> (date: Date, hasZone: Bool)? {
        guard let original = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let offset = exif?[kCGImagePropertyExifOffsetTimeOriginal as String] as? String, !offset.isEmpty {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            if let date = formatter.date(from: original + offset) { return (date, true) }
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = timeZone
        return formatter.date(from: original).map { ($0, false) }
    }

    /// The time stored in an image file.
    static func captureTime(from data: Data, timeZone: TimeZone = .current) -> (date: Date, hasZone: Bool)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return nil }
        return captureTime(exif: properties[kCGImagePropertyExifDictionary as String] as? [String: Any], timeZone: timeZone)
    }

    /// A photo picked from the library, with the time in its file.
    static func fromLibrary(_ data: Data, timeZone: TimeZone = .current) -> CapturedPhoto? {
        guard let image = UIImage(data: data) else { return nil }
        let time = captureTime(from: data, timeZone: timeZone)
        return CapturedPhoto(image: image, capturedAt: time?.date,
                             source: time.map { $0.hasZone ? .file : .fileAssumedZone })
    }

    /// A photo taken with PlowR's camera: the shutter time the camera wrote
    /// in its metadata (`UIImagePickerController`'s `.mediaMetadata`), or
    /// now if it wrote none. "Use Photo" can be tapped a while after the
    /// shutter.
    static func fromCamera(_ image: UIImage, metadata: [String: Any]?, now: Date = .now,
                           timeZone: TimeZone = .current) -> CapturedPhoto {
        let exif = metadata?[kCGImagePropertyExifDictionary as String] as? [String: Any]
        return CapturedPhoto(image: image, capturedAt: captureTime(exif: exif, timeZone: timeZone)?.date ?? now,
                             source: .camera)
    }
}

extension StopPhoto {
    var captureSource: CaptureSource? { CaptureSource(rawValue: captureSourceRaw) }

    /// Its time as the app shows it: when it was taken if known, else when
    /// it was saved.
    var displayTime: Date { capturedAt ?? takenAt }

    /// What that time is: "Taken", "File Dated", or "Added" (saved).
    var displayTimeLabel: String {
        switch captureSource {
        case .camera: "Taken"
        case .file, .fileAssumedZone: "File Dated"
        case nil: "Added"
        }
    }

    /// A visit's photos in one order, in the app and the report: before,
    /// then after, each by its time.
    static func ordered(_ photos: [StopPhoto]) -> [StopPhoto] {
        photos.sorted { ($0.isBefore ? 0 : 1, $0.displayTime) < ($1.isBefore ? 0 : 1, $1.displayTime) }
    }

    /// The photo to save from `captured` (Record Services): its capture
    /// time and where that came from go with it.
    static func make(from captured: CapturedPhoto, isBefore: Bool, operatorID: String, clientID: String,
                     routeID: String, recordID: String) -> StopPhoto? {
        guard let data = captured.image.jpegData(compressionQuality: 0.8) else { return nil }
        let photo = StopPhoto(operatorID: operatorID, clientID: clientID, routeID: routeID, isBefore: isBefore, imageData: data)
        photo.recordID = recordID
        photo.capturedAt = captured.capturedAt
        photo.captureSourceRaw = captured.source?.rawValue ?? ""
        return photo
    }
}
