import XCTest
@testable import AnimeApp

final class SmokeTests: XCTestCase {
    func testBundleLoads() {
        XCTAssertNotNil(Bundle(for: SmokeTests.self).bundleIdentifier)
    }
}
