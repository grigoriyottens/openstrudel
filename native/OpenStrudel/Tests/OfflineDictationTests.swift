import Foundation
import Darwin
import XCTest

/// Run this opt-in probe under a process sandbox that denies network access.
/// Uses the same model, audio conversion and transcriber as the application.
final class OfflineDictationTests: XCTestCase {
    func testOfflineRecognitionCancellationAndRelease() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let short = env["OPENSTRUDEL_OFFLINE_AUDIO"], let long = env["OPENSTRUDEL_OFFLINE_LONG_AUDIO"] else { throw XCTSkip("Real local audio fixtures were not supplied") }
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_port = UInt16(9).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == -1, errno == EPERM || errno == EACCES else { return XCTFail("This probe must run with outbound network access denied") }
        let transcriber = ParakeetTranscriber()
        let text = try await transcriber.transcribe(file: URL(fileURLWithPath: short))
        XCTAssertTrue(text.lowercased().contains("meeting"))
        let longRecognition = Task { try await transcriber.transcribe(file: URL(fileURLWithPath: long)) }
        try await Task.sleep(for: .milliseconds(200))
        let canceledAt = ContinuousClock.now
        longRecognition.cancel()
        do { _ = try await longRecognition.value; XCTFail("Cancellation must not return a transcript") }
        catch is CancellationError {}
        let cancelLatency = canceledAt.duration(to: .now)
        XCTAssertLessThan(cancelLatency, .seconds(5))
        let recovered = try await transcriber.transcribe(file: URL(fileURLWithPath: short))
        XCTAssertTrue(recovered.lowercased().contains("meeting"))
        let complete = try await transcriber.transcribe(file: URL(fileURLWithPath: long))
        let meetings = complete.lowercased().components(separatedBy: "meeting").count - 1
        XCTAssertEqual(meetings, 71, "Overlapping windows must preserve every phrase exactly once")
        let normalized = complete.lowercased().replacingOccurrences(of: "\\btwelve\\b", with: "12", options: .regularExpression)
        XCTAssertTrue(normalized.hasSuffix("tomorrow at 12."), "Keep the last phrase of a long recording: \(complete.suffix(240))")
        let loaded = residentBytes()
        try await Task.sleep(for: .seconds(63))
        let idle = residentBytes()
        print("Offline dictation: network denied; cancellation \(cancelLatency); \(meetings) complete phrases; resident memory loaded \(loaded / 1_048_576) MiB, idle \(idle / 1_048_576) MiB")
        XCTAssertLessThan(idle + 150 * 1_048_576, loaded, "Idle model memory should be released")
        withExtendedLifetime(transcriber) {}
    }

    private func residentBytes() -> UInt64 {
        var info = proc_taskinfo()
        _ = proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
        return info.pti_resident_size
    }
}
