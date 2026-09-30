import XCTest

@testable import DepotBar

// MARK: - Theme parsing (case-insensitive, unknown falls back to system)

final class ThemeParseTests: XCTestCase {
    func testKnownThemes() {
        XCTAssertEqual(Theme.parse("system"), .system)
        XCTAssertEqual(Theme.parse("black"), .black)
        XCTAssertEqual(Theme.parse("glass"), .glass)
    }

    func testParsingIsCaseInsensitiveAndTrims() {
        XCTAssertEqual(Theme.parse("  BLACK "), .black)
        XCTAssertEqual(Theme.parse("Glass"), .glass)
    }

    func testUnknownBlankOrMissingIsSystem() {
        XCTAssertEqual(Theme.parse("midnight"), .system)
        XCTAssertEqual(Theme.parse(""), .system)
        XCTAssertEqual(Theme.parse("   "), .system)
    }

    func testNilIsSystem() {
        XCTAssertEqual(Theme.parse(nil), .system)
    }
}

// MARK: - Config loading (env wins, then file, then system default)

final class AppConfigLoadTests: XCTestCase {
    private func tempFile(containing text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testEnvWinsOverFile() throws {
        let file = try tempFile(containing: #"{"theme":"black"}"#)
        let config = AppConfig.load(environment: ["DEPOTBAR_THEME": "glass"], fileURL: file)
        XCTAssertEqual(config.theme, .glass)
    }

    func testFileUsedWhenEnvAbsent() throws {
        let file = try tempFile(containing: #"{"theme":"black"}"#)
        XCTAssertEqual(AppConfig.load(environment: [:], fileURL: file).theme, .black)
    }

    func testMissingFileIsSystem() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        XCTAssertEqual(AppConfig.load(environment: [:], fileURL: missing).theme, .system)
    }

    func testMalformedFileIsSystem() throws {
        let file = try tempFile(containing: "not json {{{")
        XCTAssertEqual(AppConfig.load(environment: [:], fileURL: file).theme, .system)
    }

    func testUnknownThemeNameIsSystem() throws {
        let file = try tempFile(containing: #"{"theme":"midnight"}"#)
        XCTAssertEqual(AppConfig.load(environment: [:], fileURL: file).theme, .system)
    }

    func testBlankEnvFallsThroughToFile() throws {
        let file = try tempFile(containing: #"{"theme":"glass"}"#)
        XCTAssertEqual(
            AppConfig.load(environment: ["DEPOTBAR_THEME": "   "], fileURL: file).theme, .glass
        )
    }
}

// MARK: - Theme appearance mapping

final class ThemeAppearanceTests: XCTestCase {
    func testSystemFollowsTheSystem() {
        XCTAssertNil(Theme.system.menuAppearance)
    }

    func testDarkThemesForceDarkAqua() {
        XCTAssertEqual(Theme.black.menuAppearance?.name, .darkAqua)
        XCTAssertEqual(Theme.glass.menuAppearance?.name, .darkAqua)
    }
}

// MARK: - Glass icon smoke (drawing code runs headlessly and yields pixels)

final class GlassIconTests: XCTestCase {
    func testSymbolIconRenders() {
        let image = StatusIconArt.glassImage(for: .symbol(name: "checkmark.circle.fill"))
        XCTAssertEqual(image.size, StatusIconArt.size)
        XCTAssertNotNil(image.tiffRepresentation)
    }

    func testSpinnerIconRenders() {
        let image = StatusIconArt.glassImage(for: .spinner(frame: "⠋"))
        XCTAssertEqual(image.size, StatusIconArt.size)
        XCTAssertNotNil(image.tiffRepresentation)
    }
}
