//
//  PhotoCaptureTests.swift
//  PlowRTests
//

import Foundation
import ImageIO
import SwiftData
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import PlowR

/// When a job photo was taken: the camera's moment, or a library photo's
/// EXIF time; nothing guessed.
@MainActor
struct PhotoCaptureTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private let newYork = TimeZone(identifier: "America/New_York") ?? .current

    /// A small JPEG with `exif` written in, as a camera writes it.
    private func jpeg(exif: [CFString: Any]?) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let cgImage = try #require(image.cgImage)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if let exif { properties[kCGImagePropertyExifDictionary] = exif }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .current
    private let utc = TimeZone(identifier: "UTC") ?? .current
    private func instant(_ iso: String) -> Date? { ISO8601DateFormatter().date(from: iso) }

    // Zones that disagree with the file's, so the offset (or the zone used
    // without one) is what decides.
    @Test func aLibraryPhotosTimeComesFromItsFile() throws {
        let withOffset = try jpeg(exif: [kCGImagePropertyExifDateTimeOriginal: "2027:01:14 04:55:30",
                                         kCGImagePropertyExifOffsetTimeOriginal: "-05:00"])
        let read = PhotoCapture.captureTime(from: withOffset, timeZone: tokyo)
        #expect(read?.date == instant("2027-01-14T09:55:30Z") && read?.hasZone == true)
        let local = try jpeg(exif: [kCGImagePropertyExifDateTimeOriginal: "2027:01:14 04:55:30"])
        let assumed = PhotoCapture.captureTime(from: local, timeZone: utc)
        #expect(assumed?.date == instant("2027-01-14T04:55:30Z") && assumed?.hasZone == false)
        #expect(PhotoCapture.captureTime(from: try jpeg(exif: nil)) == nil)        // none is guessed
        #expect(PhotoCapture.fromLibrary(withOffset, timeZone: tokyo)?.source == .file)
        #expect(PhotoCapture.fromLibrary(local, timeZone: utc)?.source == .fileAssumedZone)
        #expect(PhotoCapture.fromLibrary(try jpeg(exif: nil))?.source == nil)
    }

    // The camera's own shutter time, not when Use Photo was tapped.
    @Test func aCameraPhotoIsTakenAtTheShutter() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }
        let metadata: [String: Any] = [kCGImagePropertyExifDictionary as String: [
            kCGImagePropertyExifDateTimeOriginal as String: "2027:01:14 04:55:30",
            kCGImagePropertyExifOffsetTimeOriginal as String: "-05:00"]]
        let shot = PhotoCapture.fromCamera(image, metadata: metadata, now: now, timeZone: tokyo)
        #expect(shot.capturedAt == instant("2027-01-14T09:55:30Z") && shot.source == .camera)
        #expect(PhotoCapture.fromCamera(image, metadata: nil, now: now).capturedAt == now)
    }

    // Saved from Record Services, a photo keeps its time and where it came from.
    @Test func aSavedPhotoKeepsItsCaptureTime() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }
        let captured = CapturedPhoto(image: image, capturedAt: Date(timeIntervalSince1970: 1_000), source: .fileAssumedZone)
        let photo = try #require(StopPhoto.make(from: captured, isBefore: false, operatorID: "op", clientID: "c",
                                                routeID: "r", recordID: "rec"))
        #expect(photo.capturedAt == Date(timeIntervalSince1970: 1_000) && photo.captureSource == .fileAssumedZone)
        #expect(photo.recordID == "rec" && !photo.isBefore)
        #expect(photo.displayTimeLabel == "File Dated")
    }

    @Test func aPhotosCaptionSaysWhatItsTimeIs() throws {
        let h = try Harness(stopCount: 0)
        let photo = StopPhoto(operatorID: "op", clientID: "c", routeID: "", isBefore: true, imageData: Data())
        h.context.insert(photo)
        let english = Locale(identifier: "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        func at(_ y: Int, _ m: Int, _ d: Int, _ hh: Int, _ mm: Int) -> Date? {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hh, minute: mm))
        }
        let visitDay = try #require(at(2027, 1, 14, 5, 0))
        func caption() -> String {
            ProofOfService.caption(of: photo, visitDay: visitDay, timeZone: newYork, locale: english, calendar: calendar)
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        #expect(caption() == "Before")                                            // time unknown: none shown
        photo.capturedAt = at(2027, 1, 14, 4, 55)
        photo.captureSourceRaw = CaptureSource.camera.rawValue
        #expect(caption() == "Before, taken 4:55 AM")
        photo.captureSourceRaw = CaptureSource.file.rawValue
        #expect(caption() == "Before, file dated 4:55 AM")
        photo.captureSourceRaw = CaptureSource.fileAssumedZone.rawValue
        #expect(caption() == "Before, file dated 4:55 AM (zone assumed)")
        // A year earlier, the same day: the year says so.
        photo.captureSourceRaw = CaptureSource.file.rawValue
        photo.capturedAt = at(2026, 1, 14, 4, 55)
        #expect(caption() == "Before, file dated Jan 14, 2026 4:55 AM")
    }

    // One order in the app and the report: before, then after, each by when taken.
    @Test func aVisitsPhotosAreInOneOrder() throws {
        let h = try Harness(stopCount: 0)
        func photo(before: Bool, saved: Double, captured: Double?) -> StopPhoto {
            let photo = StopPhoto(operatorID: "op", clientID: "c", routeID: "", isBefore: before, imageData: Data())
            photo.takenAt = Date(timeIntervalSince1970: saved)
            photo.capturedAt = captured.map { Date(timeIntervalSince1970: $0) }
            h.context.insert(photo)
            return photo
        }
        let after = photo(before: false, saved: 100, captured: 50)
        let laterBefore = photo(before: true, saved: 100, captured: 20)
        let earlierBefore = photo(before: true, saved: 100, captured: 10)
        #expect(StopPhoto.ordered([after, laterBefore, earlierBefore]).map(\.id) == [earlierBefore.id, laterBefore.id, after.id])
    }
}
