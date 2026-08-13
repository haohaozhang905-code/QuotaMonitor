import Foundation
import SQLite3
import XCTest
@testable import QuotaMonitor

final class ClaudeRouteDetectorTests: XCTestCase {
    func testDisplayRoutePrefersDeepSeekForMixedClaudeChannels() {
        XCTAssertEqual(
            ClaudeRouteSnapshot(code: .other, desktop: .deepseek).displayRoute,
            .deepseek
        )
        XCTAssertEqual(
            ClaudeRouteSnapshot(code: .official, desktop: .other).displayRoute,
            .mixed
        )
    }

    private func makeDB(withRows rows: [(appType: String, name: String, category: String, config: String, current: Bool)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccswitch-test-\(UUID().uuidString).db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        guard let db else { throw NSError(domain: "test", code: 1) }
        defer { sqlite3_close(db) }

        let create = """
        CREATE TABLE providers (
            id TEXT NOT NULL,
            app_type TEXT NOT NULL,
            name TEXT NOT NULL,
            settings_config TEXT NOT NULL,
            website_url TEXT,
            category TEXT,
            created_at INTEGER,
            sort_index INTEGER,
            notes TEXT,
            icon TEXT,
            icon_color TEXT,
            meta TEXT NOT NULL DEFAULT '{}',
            is_current BOOLEAN NOT NULL DEFAULT 0,
            in_failover_queue BOOLEAN NOT NULL DEFAULT 0,
            PRIMARY KEY (id, app_type)
        );
        """
        XCTAssertEqual(sqlite3_exec(db, create, nil, nil, nil), SQLITE_OK)

        for row in rows {
            let id = "\(row.appType)-\(row.name)"
            let sql = """
            INSERT INTO providers (id, app_type, name, settings_config, category, is_current)
            VALUES ('\(id)', '\(row.appType)', '\(row.name)', '\(row.config)', '\(row.category)', \(row.current ? 1 : 0));
            """
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, "insert \(row.name)")
        }
        return url
    }

    func testDetectsDeepSeekCurrentProviderFromCCSwitch() throws {
        let db = try makeDB(withRows: [
            ("claude-desktop", "DeepSeek", "cn_official",
             #"{"env":{"ANTHROPIC_BASE_URL":"https://api.deepseek.com/anthropic","ANTHROPIC_AUTH_TOKEN":"sk-x"}}"#, true),
            ("claude", "KomAPI", "",
             #"{"env":{"ANTHROPIC_BASE_URL":"https://www.komapi.top/"}}"#, true),
        ])
        XCTAssertEqual(ClaudeRouteDetector.detectFromCCSwitchDB(at: db), .mixed)
        XCTAssertEqual(ClaudeRouteDetector.detectFromCCSwitchDB(at: db, appType: "claude"), .other)
        XCTAssertEqual(ClaudeRouteDetector.detectFromCCSwitchDB(at: db, appType: "claude-desktop"), .deepseek)
    }

    func testDetectsOfficialCurrentProvider() throws {
        let db = try makeDB(withRows: [
            ("claude-desktop", "Claude Desktop Official", "official", #"{"env":{}}"#, true),
            ("claude", "Claude Official", "official", #"{"env":{}}"#, true),
        ])
        XCTAssertEqual(ClaudeRouteDetector.detectFromCCSwitchDB(at: db), .official)
    }

    func testThirdPartyRouteIsIdentifiedWithoutConflatingItWithDeepSeek() throws {
        let db = try makeDB(withRows: [
            ("claude", "KomAPI", "",
             #"{"env":{"ANTHROPIC_BASE_URL":"https://www.komapi.top/"}}"#, true),
        ])
        XCTAssertEqual(ClaudeRouteDetector.detectFromCCSwitchDB(at: db), .other)
    }

    func testMissingDBIsUnknown() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-db-\(UUID().uuidString).db")
        XCTAssertEqual(ClaudeRouteDetector.detectFromCCSwitchDB(at: url), .unknown)
    }

    func testSettingsFallbackStillWorks() {
        XCTAssertEqual(
            ClaudeRouteDetector.detect(settings: ["model": "deepseek-v4-flash"]),
            .deepseek
        )
        XCTAssertEqual(
            ClaudeRouteDetector.detect(settings: ["env": ["ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic"]]),
            .deepseek
        )
        XCTAssertEqual(
            ClaudeRouteDetector.detect(settings: ["model": "opus"]),
            .official
        )
    }

    func testReadsDeepSeekCredentialFromActiveProviderSettings() {
        let settings: [String: Any] = [
            "env": [
                "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
                "ANTHROPIC_AUTH_TOKEN": "test-deepseek-key",
            ]
        ]
        XCTAssertEqual(ClaudeRouteDetector.deepSeekAPIKey(settings: settings), "test-deepseek-key")
    }
}
