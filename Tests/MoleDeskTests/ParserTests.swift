import XCTest
@testable import MoleDesk

final class ParserTests: XCTestCase {
    func testParsesSectionsItemsAndCoverage() {
        let text = """
        # Mole Cleanup Preview - 2026-11-16 15:45:22
        #
        #   /Users/*/Library/Caches/com.example.app

        === User essentials ===
        /Users/me/Library/Caches/com.foo  # 1.20GB, 3 items
        /Users/me/Library/Caches/com.foo/sub  # 200.0MB, counted under /Users/me/Library/Caches/com.foo
        /Users/me/Library/Logs/odd  # name  # 512KB

        === Browsers ===
        /Users/me/Library/Caches/Google  # size unknown
        """
        let sections = CleanListParser.parse(text)
        XCTAssertEqual(sections.map(\.name), ["User essentials", "Browsers"])

        let items = sections[0].items
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].bytes, 1_200_000_000)
        XCTAssertEqual(items[0].itemCount, 3)
        XCTAssertEqual(items[1].coveredBy, "/Users/me/Library/Caches/com.foo")
        XCTAssertEqual(items[2].path, "/Users/me/Library/Logs/odd  # name")
        XCTAssertEqual(items[2].bytes, 512_000)
        // Covered rows are not double counted.
        XCTAssertEqual(sections[0].totalBytes, 1_200_512_000)

        XCTAssertNil(sections[1].items[0].bytes)
        XCTAssertEqual(sections[1].totalBytes, 0)
    }

    func testParseSize() {
        XCTAssertEqual(Fmt.parseSize("0B"), 0)
        XCTAssertEqual(Fmt.parseSize("49.0MB"), 49_000_000)
        XCTAssertEqual(Fmt.parseSize("--"), nil)
    }

    func testStripANSI() {
        XCTAssertEqual("\u{1B}[1;35m➤ Caches\u{1B}[0m".strippingANSI, "➤ Caches")
        XCTAssertEqual("frame1\rframe2".strippingANSI, "frame2")
    }

    func testDecodesUninstallList() throws {
        let json = #"[{"name": "Ollama", "bundle_id": "com.electron.ollama", "source": "App", "uninstall_name": "Ollama", "path": "/Applications/Ollama.app", "size": "333.9MB"}]"#
        let apps = try JSONDecoder().decode([InstalledApp].self, from: Data(json.utf8))
        XCTAssertEqual(apps.first?.sizeBytes, 333_900_000)
    }
}
