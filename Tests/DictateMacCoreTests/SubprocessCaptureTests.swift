import XCTest
@testable import DictateMacCore

final class SubprocessCaptureTests: XCTestCase {
    func testCapturesOutputLargerThanPipeBufferWithoutDeadlock() async throws {
        let result = try await SubprocessCapture.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/seq"),
            arguments: ["1", "20000"]
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertGreaterThan(result.stdout.count, 65_536)
        XCTAssertTrue(String(decoding: result.stdout, as: UTF8.self).hasSuffix("20000\n"))
    }
}
