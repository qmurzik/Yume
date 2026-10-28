import Foundation
import XCTest

enum Fixture {
    static func data(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        if let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") {
            return try Data(contentsOf: url)
        }
        // Running from a plain checkout (e.g. swift test): read next to this file.
        let local = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
            .appendingPathComponent("Fixtures").appendingPathComponent("\(name).json")
        if FileManager.default.fileExists(atPath: local.path) { return try Data(contentsOf: local) }
        XCTFail("Missing fixture \(name).json", file: file, line: line)
        throw CocoaError(.fileNoSuchFile)
    }
}

private final class BundleToken {}
