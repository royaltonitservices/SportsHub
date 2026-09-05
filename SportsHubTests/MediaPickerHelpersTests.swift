//
//  MediaPickerHelpersTests.swift
//  SportsHubTests
//
//  Gate 1.1 photo-picker functional-parity coverage:
//   - evidence video MIME is derived truthfully from the real extension
//     (MP4 is never relabeled as MOV)
//   - avatar center-square crop preserves the legacy allowsEditing square result
//

import Testing
import UIKit
@testable import SportsHub

struct EvidenceVideoMIMETests {
    @Test func movIsQuickTime() {
        #expect(evidenceVideoMIMEType(forExtension: "mov") == "video/quicktime")
        #expect(evidenceVideoMIMEType(forExtension: "MOV") == "video/quicktime")
    }
    @Test func mp4IsMP4() {
        #expect(evidenceVideoMIMEType(forExtension: "mp4") == "video/mp4")
        #expect(evidenceVideoMIMEType(forExtension: "m4v") == "video/mp4")
    }
    @Test func mp4NeverRelabeledAsMov() {
        #expect(evidenceVideoMIMEType(forExtension: "mp4") != "video/quicktime")
    }
    @Test func unknownFallsBackToVideoMP4() {
        #expect(evidenceVideoMIMEType(forExtension: "") == "video/mp4")
        #expect(evidenceVideoMIMEType(forExtension: "xyz") == "video/mp4")
    }
    @Test func bothTypesAreBackendAccepted() {
        // Backend evidence upload allows exactly these two video MIME types.
        let accepted: Set<String> = ["video/mp4", "video/quicktime"]
        #expect(accepted.contains(evidenceVideoMIMEType(forExtension: "mov")))
        #expect(accepted.contains(evidenceVideoMIMEType(forExtension: "mp4")))
    }
}

struct AvatarCropTests {
    private func solidImage(_ w: CGFloat, _ h: CGFloat) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
    }
    @Test func wideImageBecomesSquare() {
        let out = solidImage(100, 40).centerSquareCropped()
        #expect(out.size.width == out.size.height)
        #expect(out.size.width == 40)
    }
    @Test func tallImageBecomesSquare() {
        let out = solidImage(30, 90).centerSquareCropped()
        #expect(out.size.width == out.size.height)
        #expect(out.size.width == 30)
    }
    @Test func squareImageUnchanged() {
        let out = solidImage(50, 50).centerSquareCropped()
        #expect(out.size.width == 50 && out.size.height == 50)
    }
}
