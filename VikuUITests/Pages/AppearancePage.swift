import CoreGraphics
import UIKit
import XCTest

@MainActor
struct AppearancePage {
    enum Option: String, CaseIterable {
        case light
        case dark
        case automatic = "system"
    }

    let app: XCUIApplication

    private func tile(_ option: Option) -> XCUIElement {
        app.buttons["settings.appearance.option.\(option.rawValue)"]
    }

    func assertVisible(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(tile(.automatic).waitForExistence(timeout: 5), file: file, line: line)
    }

    func assertTwoColumns(file: StaticString = #filePath, line: UInt = #line) {
        let automatic = tile(.automatic).frame
        let light = tile(.light).frame
        let dark = tile(.dark).frame
        XCTAssertEqual(automatic.minY, light.minY, accuracy: 1, file: file, line: line)
        XCTAssertLessThan(automatic.maxX, light.minX, file: file, line: line)
        XCTAssertEqual(automatic.minX, dark.minX, accuracy: 1, file: file, line: line)
        XCTAssertLessThan(automatic.maxY, dark.minY, file: file, line: line)
    }

    func assertNoteAbovePreviews(file: StaticString = #filePath, line: UInt = #line) {
        let note = app.staticTexts["settings.appearance.note"]
        XCTAssertTrue(note.isHittable, file: file, line: line)
        XCTAssertLessThan(note.frame.maxY, tile(.automatic).frame.minY, file: file, line: line)
        let expected = "The theme changes buttons, checkboxes, and accents. "
            + "Your project and label colors stay the same."
        XCTAssertEqual(
            note.label, expected, file: file, line: line,
        )
    }

    func select(_ option: Option, file: StaticString = #filePath, line: UInt = #line) {
        tile(option).tap()
        XCTAssertTrue(tile(option).wait(for: \.isSelected, toEqual: true, timeout: 5), file: file, line: line)
        for other in Option.allCases where other != option {
            XCTAssertFalse(tile(other).isSelected, file: file, line: line)
        }
    }

    func assertRenderedAppearance(dark: Bool, name: String, file: StaticString = #filePath, line: UInt = #line) {
        // Check actual rendered pixels, independently of the selected option or ThemeCenter.
        let matches = dark
            ? app.wait(for: \.hasDarkGridBackground, toEqual: true, timeout: 5)
            : app.wait(for: \.hasLightGridBackground, toEqual: true, timeout: 5)
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        XCTAssertTrue(matches, file: file, line: line)
    }

    func assertThemePreviews(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(tile(.light).label, "Theme Viku Light", file: file, line: line)
        XCTAssertEqual(tile(.dark).label, "Theme Viku Dark", file: file, line: line)
        XCTAssertGreaterThan(tile(.light).previewBackgroundBrightness(onRight: false), 0.75, file: file, line: line)
        XCTAssertLessThan(tile(.dark).previewBackgroundBrightness(onRight: false), 0.35, file: file, line: line)
        XCTAssertGreaterThan(tile(.automatic).previewBackgroundBrightness(onRight: false), 0.75, file: file, line: line)
        XCTAssertLessThan(tile(.automatic).previewBackgroundBrightness(onRight: true), 0.35, file: file, line: line)
    }

    func assertSelectionRing(_ selected: Option, file: StaticString = #filePath, line: UInt = #line) {
        guard let image = app.screenshot().image.cgImage else {
            XCTFail("Could not capture preview bounds", file: file, line: line)
            return
        }
        let scale = CGFloat(image.width) / app.frame.width
        for option in Option.allCases {
            let bounds = tile(option).frame
            let y = (bounds.minY + bounds.width * 0.44) * scale
            // Sample the selection ring and the gap between the ring and the preview.
            let ring = CGRect(x: (bounds.minX - 3.75) * scale, y: y, width: 1, height: 1)
            let gap = CGRect(x: (bounds.minX - 1.25) * scale, y: y, width: 1, height: 1)
            let accentBrightness = 0.35 ... 0.65
            XCTAssertEqual(
                image.brightness(in: ring).map(accentBrightness.contains),
                option == selected,
                option.rawValue,
                file: file,
                line: line,
            )
            XCTAssertEqual(
                image.brightness(in: gap).map(accentBrightness.contains),
                false,
                option.rawValue,
                file: file,
                line: line,
            )
        }
    }
}

private extension XCUIElement {
    var hasDarkGridBackground: Bool {
        gridBackgroundBrightness.map { $0 < 0.35 } ?? false
    }

    var hasLightGridBackground: Bool {
        gridBackgroundBrightness.map { $0 > 0.75 } ?? false
    }

    var gridBackgroundBrightness: Double? {
        guard let image = screenshot().image.cgImage else { return nil }
        // Sample the gutter between the first two previews.
        let automatic = buttons["settings.appearance.option.system"].frame
        let light = buttons["settings.appearance.option.light"].frame
        let scale = CGFloat(image.width) / frame.width
        let x = (automatic.maxX + light.minX) / 2 * scale
        let y = automatic.midY * scale
        return image.brightness(in: CGRect(x: x, y: y, width: 2, height: 2))
    }

    func previewBackgroundBrightness(onRight: Bool) -> Double {
        guard let image = screenshot().image.cgImage else { return .nan }
        // Sample between the chips and the task list in the preview.
        let width = Double(image.width)
        let region = CGRect(x: width * (onRight ? 0.67 : 0.33), y: width * 0.30, width: 2, height: 2)
        return image.brightness(in: region) ?? .nan
    }
}

private extension CGImage {
    func brightness(in region: CGRect) -> Double? {
        guard let sample = cropping(to: region.integral) else { return nil }
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
