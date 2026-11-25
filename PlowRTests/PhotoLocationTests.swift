import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import PlowR

/// A picked photo or logo is kept without the location its file carries.
struct PhotoLocationTests {
    private func image(type: UTType, properties: [CFString: Any]) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let cgImage = try #require(picture.cgImage)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test func aGeotaggedPhotoLosesItsLocationAndKeepsItsTime() throws {
        let tagged = try image(type: .jpeg, properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 43.6, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 79.4, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2027:01:14 04:55:00"]
        ])
        #expect(try properties(of: tagged)[kCGImagePropertyGPSDictionary] != nil)   // the fixture carries it
        let kept = try #require(PhotoCapture.removingLocation(from: tagged))
        let after = try properties(of: kept)
        #expect(after[kCGImagePropertyGPSDictionary] == nil)
        let exif = after[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2027:01:14 04:55:00")
        #expect(PhotoCapture.captureTime(from: kept) != nil)
    }

    private var gps: [CFString: Any] {
        [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 43.6, kCGImagePropertyGPSLatitudeRef: "N",
                                         kCGImagePropertyGPSLongitude: 79.4, kCGImagePropertyGPSLongitudeRef: "W"]]
    }

    // ImageIO's lossless copy reports success for a PNG and keeps the location.
    @Test func aGeotaggedLogoLosesItsLocationAndKeepsItsFormat() throws {
        let png = try image(type: .png, properties: gps)
        #expect(PhotoCapture.hasLocation(png))
        let kept = try #require(PhotoCapture.removingLocation(from: png))
        #expect(!PhotoCapture.hasLocation(kept))
        let source = try #require(CGImageSourceCreateWithData(kept as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
    }

    @Test func anImageWithNoLocationIsKeptAsItIs() throws {
        let png = try image(type: .png, properties: [:])
        #expect(PhotoCapture.removingLocation(from: png) == png)
    }

    @Test func somethingThatIsntAnImageIsNotKept() {
        #expect(PhotoCapture.removingLocation(from: Data("not an image".utf8)) == nil)
    }

    // The step the client's gallery and an expense's receipt share
    // (PhotoCapture.saving): a picked photo is kept without its location,
    // with the time read from the original file.
    @MainActor @Test func aPickedPhotoIsSavedWithoutItsLocationAndWithItsTime() async throws {
        var properties = gps
        properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifDateTimeOriginal: "2027:01:14 04:55:00"]
        let tagged = try image(type: .jpeg, properties: properties)
        let utc = try #require(TimeZone(identifier: "UTC"))
        let saved = try #require(await PhotoCapture.saving(library: tagged, timeZone: utc))
        let stripped: Bool = !PhotoCapture.hasLocation(saved.data)
        #expect(stripped)
        let expected = Date(timeIntervalSince1970: 1_799_902_500)   // 2027-01-14 04:55:00 UTC
        #expect(saved.capture.capturedAt == expected)
        #expect(saved.capture.source == .fileAssumedZone)
    }

    @MainActor @Test func aPickedFileThatIsntAnImageIsRefused() async {
        let saved = await PhotoCapture.saving(library: Data("not an image".utf8))
        #expect(saved == nil)
    }

    // A camera photo is saved as a JPEG with the shutter time.
    @MainActor @Test func aCameraPhotoIsSavedAsAJPEGAtTheShutter() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).image { _ in }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let saved = try #require(PhotoCapture.saving(camera: picture, metadata: nil, now: now))
        let source = try #require(CGImageSourceCreateWithData(saved.data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        #expect(saved.capture.capturedAt == now)
        #expect(saved.capture.source == .camera)
    }
}
