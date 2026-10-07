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
}
