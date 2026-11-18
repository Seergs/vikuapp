import CoreGraphics
import UIKit
import XCTest

@MainActor
struct AppearancePage {
    enum Option: String {
        case light
        case dark
        case automatic = "system"
    }

    let app: XCUIApplication

    private func row(_ option: Option) -> XCUIElement {
        app.buttons["settings.appearance.option.\(option.rawValue)"]
    }

    func assertVisible(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(row(.automatic).waitForExistence(timeout: 5), file: file, line: line)
    }

    func select(_ option: Option, file: StaticString = #filePath, line: UInt = #line) {
        row(option).tap()
        XCTAssertTrue(row(option).wait(for: \.isSelected, toEqual: true, timeout: 5), file: file, line: line)
    }

    func assertRenderedAppearance(dark: Bool, name: String, file: StaticString = #filePath, line: UInt = #line) {
        // Check actual rendered pixels, independently of the selected option or ThemeCenter.
        let matches = dark
            ? row(.automatic).wait(for: \.hasDarkCardBackground, toEqual: true, timeout: 5)
            : row(.automatic).wait(for: \.hasLightCardBackground, toEqual: true, timeout: 5)
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        XCTAssertTrue(matches, file: file, line: line)
    }
}

private extension XCUIElement {
    var hasDarkCardBackground: Bool {
        cardBackgroundBrightness.map { $0 < 0.35 } ?? false
    }

    var hasLightCardBackground: Bool {
        cardBackgroundBrightness.map { $0 > 0.75 } ?? false
    }

    var cardBackgroundBrightness: Double? {
        guard let image = screenshot().image.cgImage else { return nil }
        // Sample the empty spacer between the option title and its trailing checkmark.
        // The crop scales with the row; no screen coordinates or exact palette RGBs are assumed.
        let region = CGRect(
            x: Double(image.width) * 0.6, y: Double(image.height) * 0.25,
            width: Double(image.width) * 0.2, height: Double(image.height) * 0.5,
        ).integral
        guard let sample = image.cropping(to: region) else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return false }
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard rendered else { return nil }
        return (Double(rgba[0]) + Double(rgba[1]) + Double(rgba[2])) / (3 * 255)
    }
}
