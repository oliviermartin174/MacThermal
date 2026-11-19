import XCTest

final class ThermalModelTests: XCTestCase {
    private func reading(_ id: String, _ value: Double?) -> Reading {
        Reading(id: id, label: id, value: value, source: "test")
    }
    private func threshold(_ r: Reading) -> Double { r.id == "cpu" ? 75 : 85 }

    func testIndependentThresholdsAndSingleAlertPerEpisode() {
        var state = AlertState()
        XCTAssertTrue(state.update([reading("cpu", 74), reading("gpu", 84)], threshold: threshold).isEmpty)
        XCTAssertEqual(state.update([reading("cpu", 75), reading("gpu", 84)], threshold: threshold).map(\.id), ["cpu"])
        XCTAssertEqual(state.update([reading("cpu", 80), reading("gpu", 85)], threshold: threshold).map(\.id), ["gpu"])
        XCTAssertTrue(state.update([reading("cpu", 81), reading("gpu", 86)], threshold: threshold).isEmpty)
    }

    func testCoolingHysteresisAndRearming() {
        var state = AlertState()
        _ = state.update([reading("cpu", 75)], threshold: threshold)
        _ = state.update([reading("cpu", 71)], threshold: threshold)
        XCTAssertTrue(state.hot.contains("cpu"))
        _ = state.update([reading("cpu", 70)], threshold: threshold)
        XCTAssertTrue(state.hot.isEmpty)
        XCTAssertEqual(state.update([reading("cpu", 75)], threshold: threshold).count, 1)
    }

    func testMissingReadingRetainsAlertAndRemovedDeviceIsDiscarded() {
        var state = AlertState()
        _ = state.update([reading("gpu", 85)], threshold: threshold)
        XCTAssertTrue(state.update([reading("gpu", nil)], threshold: threshold).isEmpty)
        XCTAssertTrue(state.hot.contains("gpu"))
        _ = state.update([reading("cpu", 30)], threshold: threshold)
        XCTAssertTrue(state.hot.isEmpty)
        XCTAssertEqual(reading("cpu", nil).formatted, "indisponible")
    }

    func testFanControlSimulationsWithoutHardwareWrites() throws {
        let executable = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "FanAssistTests", withExtension: nil))
        let process = Process()
        process.executableURL = executable
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, text)
        XCTAssertTrue(text.contains("OK :"), text)
    }
}
