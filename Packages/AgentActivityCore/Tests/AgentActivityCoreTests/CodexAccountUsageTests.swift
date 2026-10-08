import XCTest
@testable import AgentActivityCore

final class CodexAccountUsageTests: XCTestCase {
    func testNamedBucketsTakePrecedenceAndKeepProviderDurationsAndResets() throws {
        let responseBody = Data(#"{"rateLimits":{"limitId":"legacy","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":40,"windowDurationMins":10080}},"reserve":{"limitName":"Reserve","primary":{"usedPercent":0,"windowDurationMins":60}}}}"#.utf8)
        let usage = try CodexRateLimitsDecoder().decodeResponse(from: responseBody)
        XCTAssertEqual(usage.usageWindows.map(\.usedPercentage), [25, 40, 0])
        XCTAssertEqual(usage.usageWindows.map(\.windowLabel), ["codex · 5 hours", "codex · 7 days", "Reserve · 1 hour"])
        XCTAssertEqual(usage.usageWindows.first?.resetsAt, Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertNil(usage.usageWindows[1].resetsAt)
    }

    func testNullMissingAndInvalidWindowsDoNotInventZeroUsage() throws {
        let responseBody = Data(#"{"rateLimits":{"limitId":"codex","primary":{"windowDurationMins":300},"secondary":null}}"#.utf8)
        XCTAssertTrue(try CodexRateLimitsDecoder().decodeResponse(from: responseBody).usageWindows.isEmpty)
        let negativeUsage = Data(#"{"rateLimits":{"primary":{"usedPercent":-1},"secondary":{"usedPercent":110}}}"#.utf8)
        XCTAssertEqual(try CodexRateLimitsDecoder().decodeResponse(from: negativeUsage).usageWindows.map(\.usedPercentage), [110])
        XCTAssertThrowsError(try CodexRateLimitsDecoder().decodeResponse(from: Data("{}".utf8)))
        XCTAssertThrowsError(try CodexRateLimitsDecoder().decodeResponse(from: Data(#"{"rateLimits":{"primary":{"usedPercent":"wrong"}}}"#.utf8)))
    }

    func testLegacyBucketWithoutDurationStaysUnspecified() throws {
        let responseBody = Data(#"{"rateLimits":{"primary":{"usedPercent":5},"secondary":{"usedPercent":12,"windowDurationMins":15}}}"#.utf8)
        let usage = try CodexRateLimitsDecoder().decodeResponse(from: responseBody)
        XCTAssertEqual(usage.usageWindows.map(\.windowLabel), ["codex · Primary window", "codex · 15 minutes"])
        XCTAssertNil(usage.usageWindows.first?.windowDurationMinutes)
    }

    func testStdioHandshakeReadsOnlyAccountQuota() async throws {
        let fixtureExecutable = try makeFixtureExecutable(named: "codex-usage-server")
        defer { try? FileManager.default.removeItem(at: fixtureExecutable.deletingLastPathComponent()) }
        let usage = try await CodexAccountUsageReader(executableURL: fixtureExecutable, timeout: 3).readUsage()
        XCTAssertEqual(usage.usageWindows.first?.usedPercentage, 25)
        XCTAssertEqual(usage.usageWindows.first?.windowDurationMinutes, 300)
    }

    func testStdioServerErrorIsSanitized() async throws {
        let fixtureExecutable = try makeFixtureExecutable(named: "codex-usage-error-server")
        defer { try? FileManager.default.removeItem(at: fixtureExecutable.deletingLastPathComponent()) }
        do {
            _ = try await CodexAccountUsageReader(executableURL: fixtureExecutable, timeout: 3).readUsage()
            XCTFail("Expected a quota request error")
        } catch {
            XCTAssertEqual(error as? CodexAccountUsageError, .requestFailed)
            XCTAssertFalse(String(describing: error).contains("private upstream detail"))
        }
    }

    func testStdioTimeoutIsBounded() async throws {
        let fixtureExecutable = try makeFixtureExecutable(named: "codex-usage-timeout-server")
        defer { try? FileManager.default.removeItem(at: fixtureExecutable.deletingLastPathComponent()) }
        let requestedAt = Date()
        do {
            _ = try await CodexAccountUsageReader(executableURL: fixtureExecutable, timeout: 1).readUsage()
            XCTFail("Expected a timeout")
        } catch {
            XCTAssertEqual(error as? CodexAccountUsageError, .timedOut)
            XCTAssertLessThan(Date().timeIntervalSince(requestedAt), 3)
        }
    }

    private func makeFixtureExecutable(named fixtureName: String) throws -> URL {
        let fixtureSource = try XCTUnwrap(Bundle.module.url(forResource: fixtureName, withExtension: "sh"))
        let fixtureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
        let executable = fixtureDirectory.appendingPathComponent(fixtureName)
        try FileManager.default.copyItem(at: fixtureSource, to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return executable
    }
}
