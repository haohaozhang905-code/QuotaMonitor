import Foundation
import Testing
@testable import QuotaMonitor

struct QuotaModelsTests {
    @Test func canonicalModelNamesMergeAutoAndUnknownBuckets() {
        let day = Date(timeIntervalSince1970: 1_786_400_000)
        let buckets = [
            Self.bucket(day: day, platform: .codex, client: .cli, model: "auto", total: 20),
            Self.bucket(day: day, platform: .codex, client: .cli, model: " UNKNOWN ", total: 30),
            Self.bucket(day: day, platform: .codex, client: .cli, model: "", total: 40),
            Self.bucket(day: day, platform: .codex, client: .cli, model: "gpt-5.6-sol", total: 50),
            Self.bucket(day: day, platform: .codex, client: .cli, model: "DeepSeek V4 flash", total: 30),
            Self.bucket(day: day, platform: .codex, client: .cli, model: "deepseek v4 flash", total: 20)
        ]

        let combined = TokenUsageBucket.combining(buckets)
        let presentation = QuotaPresentationSnapshot.make(
            providers: [],
            updatedAt: day,
            errorMessageKey: nil,
            isRefreshing: false,
            codexRoute: .official,
            claudeRoute: .unknown,
            totalHistory: [],
            buckets: buckets,
            now: day
        )

        #expect(TokenModelName.canonical(" AUTO ") == "unknown")
        #expect(TokenModelName.canonical("unknown") == "unknown")
        #expect(TokenModelName.canonical(" DeepSeek V4 flash ") == "deepseek v4 flash")
        #expect(TokenModelName.canonical(" gpt-5.6-sol ") == "gpt-5.6-sol")
        #expect(combined.count == 3)
        #expect(combined.first { $0.model == "unknown" }?.total == 90)
        #expect(combined.first { $0.model == "gpt-5.6-sol" }?.total == 50)
        #expect(combined.first { $0.model == "deepseek v4 flash" }?.total == 50)
        #expect(presentation.modelToday.count == 3)
        #expect(presentation.modelToday.first { $0.key == .model("unknown") }?.total == 90)
    }

    @Test func presentationSnapshotUsesSharedDenominatorsAndGroupsOtherModels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 12))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let history = [
            DailyTokenUsage(day: now, totals: TokenTotals(input: 90, output: 10)),
            DailyTokenUsage(day: yesterday, totals: TokenTotals(input: 40, output: 10))
        ]
        let buckets = [
            Self.bucket(day: now, platform: .codex, client: .cli, model: "model-a", total: 60),
            Self.bucket(day: now, platform: .claude, client: .desktop, model: "model-b", total: 20),
            Self.bucket(day: now, platform: .claude, client: .cli, model: "model-c", total: 10),
            Self.bucket(day: now, platform: .workbuddy, client: .desktop, model: "model-d", total: 10),
            Self.bucket(day: yesterday, platform: .codex, client: .cli, model: "model-old", total: 500)
        ]

        let snapshot = QuotaPresentationSnapshot.make(
            providers: [],
            updatedAt: now,
            errorMessageKey: nil,
            isRefreshing: false,
            codexRoute: .official,
            claudeRoute: .official,
            totalHistory: history,
            buckets: buckets,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.availability == .ready)
        #expect(snapshot.today.total == 100)
        #expect(snapshot.today.trendPercent == 100)
        #expect(snapshot.platformToday.map(\.total) == [60, 20, 10, 10])
        #expect(snapshot.platformToday.reduce(0.0) { $0 + $1.share } == 1)
        #expect(snapshot.modelToday.map(\.total) == [60, 20, 10, 10])
        #expect(snapshot.topModels().map(\.total) == [60, 20, 10, 10])
        #expect(snapshot.topModels().last?.key == .model("model-d"))
    }

    @Test func dashboardBreakdownsUseFourPlusOtherForPlatformsAndModels() {
        let now = Date(timeIntervalSince1970: 1_786_400_000)
        let platforms: [TokenPlatform] = [.codex, .claude, .workbuddy, .kimi]
        var buckets = platforms.enumerated().map { index, platform in
            Self.bucket(day: now, platform: platform, client: .desktop, model: "model-\(index)", total: 100 - index * 10)
        }
        buckets.append(Self.bucket(day: now, platform: .codex, client: .cli, model: "model-4", total: 50))
        buckets.append(Self.bucket(day: now, platform: .codex, client: .plugin, model: "model-5", total: 40))

        let dashboard = QuotaPresentationSnapshot.makeTokenDashboard(
            period: .all,
            totalHistory: [],
            buckets: buckets,
            now: now
        )

        #expect(dashboard.platform.count == 5)
        #expect(dashboard.platform.last?.key == .otherPlatforms)
        #expect(dashboard.platform.map(\.total) == [100, 90, 80, 70, 90])
        #expect(dashboard.models.count == 5)
        #expect(dashboard.models.last?.key == .otherModels)
        #expect(dashboard.models.map(\.total) == [100, 90, 80, 70, 90])
    }

    @Test func presentationSnapshotDistinguishesConnectedOnlyFromUnavailable() {
        let connected = QuotaPresentationSnapshot.make(
            providers: [], updatedAt: nil, errorMessageKey: nil, isRefreshing: false,
            codexRoute: .official, claudeRoute: .unknown, totalHistory: [], buckets: []
        )
        let unavailable = QuotaPresentationSnapshot.make(
            providers: [], updatedAt: nil, errorMessageKey: nil, isRefreshing: false,
            codexRoute: .unknown, claudeRoute: .unknown, totalHistory: [], buckets: []
        )
        #expect(connected.availability == .connectedOnly)
        #expect(unavailable.availability == .unavailable)
    }

    @Test func presentationSnapshotKeepsOldDataAsStaleAfterRefreshFailure() {
        let snapshot = QuotaPresentationSnapshot.make(
            providers: [],
            updatedAt: .now,
            errorMessageKey: "error.network",
            isRefreshing: false,
            codexRoute: .official,
            claudeRoute: .unknown,
            totalHistory: [DailyTokenUsage(day: .now, totals: TokenTotals(input: 100))],
            buckets: []
        )

        #expect(snapshot.availability == .stale)
    }

    @Test func dropdownPresentationDistinguishesQuotaConnectionStates() {
        let connected = QuotaPresentationSnapshot.make(
            providers: [], updatedAt: nil, errorMessageKey: nil, isRefreshing: false,
            codexRoute: .official, claudeRoute: .unknown, totalHistory: [], buckets: []
        )
        let noQuota = QuotaPresentationSnapshot.makeDropdown(
            presentation: connected,
            providers: [],
            codexRoute: .official,
            claudeRoute: .unknown,
            deepSeekBalance: nil,
            deepSeekCurrency: nil,
            deepSeekDays: nil
        )
        #expect(noQuota.availability == .connectedOnly)
        #expect(noQuota.quotaItems.map(\.platform) == [.codex])
        #expect(noQuota.quotaItems.first?.state == .connectedWithoutQuota)

        let sharedBalance = QuotaPresentationSnapshot.makeDropdown(
            presentation: connected,
            providers: [],
            codexRoute: .deepseek,
            claudeRoute: .deepseek,
            deepSeekBalance: 12.26,
            deepSeekCurrency: "CNY",
            deepSeekDays: 7
        )
        #expect(sharedBalance.quotaItems.map(\.platform) == [.codex, .claude])
        #expect(sharedBalance.quotaItems.allSatisfy {
            $0.state == .sharedBalance(amount: 12.26, currency: "CNY", estimatedDays: 7)
        })
    }

    @Test func dropdownKeepsExactlyFiveCategoriesWithoutOtherRows() {
        let now = Date(timeIntervalSince1970: 1_786_400_000)
        let platforms: [TokenPlatform] = [.codex, .claude, .workbuddy, .kimi, .opencode]
        let buckets = platforms.enumerated().map { index, platform in
            Self.bucket(
                day: now,
                platform: platform,
                client: .desktop,
                model: "model-\(index)",
                total: 100 - index * 10
            )
        }
        let presentation = QuotaPresentationSnapshot.make(
            providers: [],
            updatedAt: now,
            errorMessageKey: nil,
            isRefreshing: false,
            codexRoute: .official,
            claudeRoute: .official,
            totalHistory: [DailyTokenUsage(day: now, totals: TokenTotals(input: 400))],
            buckets: buckets,
            now: now
        )
        let dropdown = QuotaPresentationSnapshot.makeDropdown(
            presentation: presentation,
            providers: [],
            codexRoute: .official,
            claudeRoute: .official,
            deepSeekBalance: nil,
            deepSeekCurrency: nil,
            deepSeekDays: nil
        )

        #expect(dropdown.platformToday.count == 5)
        #expect(dropdown.platformToday.last?.key != .otherPlatforms)
        #expect(dropdown.topModels.count == 5)
        #expect(dropdown.topModels.last?.key != .otherModels)
    }

    @Test func tokenDashboardUsesNaturalDaysForTotalsAndAverages() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 12))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let history = [
            DailyTokenUsage(day: yesterday, totals: TokenTotals(input: 50)),
            DailyTokenUsage(day: now, totals: TokenTotals(input: 100))
        ]
        let dashboard = QuotaPresentationSnapshot.makeTokenDashboard(
            period: .sevenDays,
            totalHistory: history,
            buckets: [
                Self.bucket(day: now, platform: .codex, client: .cli, model: "model-a", total: 100),
                Self.bucket(day: yesterday, platform: .claude, client: .cli, model: "model-b", total: 50)
            ],
            now: now,
            calendar: calendar
        )

        #expect(dashboard.summary.total == 150)
        #expect(dashboard.summary.dayCount == 7)
        #expect(dashboard.summary.average == 21)
        #expect(dashboard.summary.peak == 100)
        #expect(dashboard.platform.map(\.total) == [100, 50])
        #expect(dashboard.models.map(\.total) == [100, 50])
    }

    private static func bucket(
        day: Date,
        platform: TokenPlatform,
        client: TokenClient,
        model: String,
        total: Int
    ) -> TokenUsageBucket {
        TokenUsageBucket(
            bucketStart: day,
            platform: platform,
            client: client,
            model: model,
            provider: .official,
            totals: TokenTotals(input: total)
        )
    }

    @Test func decodesUsageAndComputesRemaining() throws {
        let json = #"[{"providerId":"codex","displayName":"Codex","plan":"Pro","lines":[{"type":"progress","label":"Session","used":17,"limit":100,"resetsAt":"2026-07-12T18:17:13.000Z","periodDurationMs":18000000}],"fetchedAt":"2026-07-12T15:44:43.909678Z"}]"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        let result = try decoder.decode([ProviderUsage].self, from: json)
        #expect(result[0].session?.remainingPercent == 0.83)
        #expect(result[0].session?.resetsAt != nil)
        #expect(result[0].balanceCurrency == nil)
    }

    @Test func healthThresholds() {
        #expect(QuotaHealth(remaining: 0.8) == .healthy)
        #expect(QuotaHealth(remaining: 0.51) == .healthy)
        #expect(QuotaHealth(remaining: 0.50) == .warning)
        #expect(QuotaHealth(remaining: 0.11) == .warning)
        #expect(QuotaHealth(remaining: 0.10) == .critical)
    }

    @Test func balanceProviderExposesAmountAndDays() {
        let provider = ProviderUsage(
            providerId: "codex",
            displayName: "Codex",
            plan: "余额制",
            lines: [
                UsageLine(
                    type: "balance",
                    label: "balance",
                    used: 12.26,
                    limit: 7,
                    resetsAt: nil,
                    periodDurationMs: nil,
                    value: "¥12.26",
                    subtitle: "7"
                )
            ],
            fetchedAt: nil,
            balanceCurrency: "CNY",
            model: "deepseek-v4-flash"
        )
        #expect(provider.balanceAmount == 12.26)
        #expect(provider.balanceDays == 7)
        #expect(provider.balanceCurrency == "CNY")
        #expect(provider.model == "deepseek-v4-flash")
    }

    @Test func routeDetectionPrefersOfficialToken() throws {
        let officialAuth = #"{"tokens":{"access_token":"sk-abc"}}"#.data(using: .utf8)
        let deepseekAuth = #"{"OPENAI_API_KEY":"sk-abc"}"#.data(using: .utf8)
        let deepseekConfig = """
        model_provider = "custom"
        [model_providers.custom]
        base_url = "https://api.deepseek.com"
        """
        #expect(CodexRouteDetector.detect(authData: officialAuth, configText: deepseekConfig) == .deepseek)
        #expect(CodexRouteDetector.detect(authData: officialAuth, configText: nil) == .official)
        #expect(CodexRouteDetector.detect(authData: deepseekAuth, configText: deepseekConfig) == .deepseek)
        #expect(CodexRouteDetector.detect(authData: deepseekAuth, configText: nil) == .official)
        #expect(CodexRouteDetector.detect(authData: nil, configText: nil) == .unknown)
    }

    @Test func currentModelParsesConfig() {
        let config = """
        model_provider = "custom"
        model = "deepseek-v4-flash"
        [model_providers.custom]
        base_url = "https://api.deepseek.com"
        """
        #expect(CodexRouteDetector.currentModel(configText: config) == "deepseek-v4-flash")
        #expect(CodexRouteDetector.currentModel(configText: nil) == nil)
    }

    @Test func costEstimatorComputesSpendAndDays() {
        let totals = TokenTotals(
            input: 1_000_000,
            cachedInput: 500_000,
            cacheWriteInput: 100_000,
            output: 200_000,
            reasoning: 100_000
        )
        let cost = TokenCostEstimator.estimatedCost(tokens: totals, model: "deepseek-v4-flash")
        // reasoning 是 completion_tokens 的明细：未命中 500k×1 + 命中 500k×0.02 + 输出 200k×2。
        #expect(abs((cost ?? 0) - 0.91) < 0.0001)

        let buckets = [TokenUsageBucket(
            bucketStart: .now,
            platform: .codex,
            client: .cli,
            model: "deepseek-v4-flash",
            provider: .deepseek,
            totals: totals
        )]
        // 只有今天有消耗时仍然除以七个自然日：0.91 / 7 = 0.13 元/日。
        #expect(TokenCostEstimator.daysSupported(balance: 0.9, currency: "CNY", buckets: buckets) == 6)
        #expect(TokenCostEstimator.daysSupported(balance: 10.9, currency: "CNY", buckets: []) == nil)
        #expect(TokenCostEstimator.estimatedCost(tokens: totals, currency: "EUR") == nil)
        let usdCost = TokenCostEstimator.estimatedCost(
            tokens: totals,
            model: "deepseek-v4-pro",
            currency: "USD"
        )
        #expect(abs((usdCost ?? 0) - 0.3933125) < 0.0000001)
        #expect(TokenCostEstimator.cacheHitRate(tokens: DailyTokenUsage(day: .now, totals: totals)) == 0.5)
    }

    @Test func moneyFormatterTrimsTrailingZeros() {
        #expect(QuotaFormatters.money(12.26, currency: "CNY") == "¥12.26")
        #expect(QuotaFormatters.money(12.00, currency: "CNY") == "¥12")
        #expect(QuotaFormatters.money(0.84, currency: "CNY") == "¥0.84")
        #expect(QuotaFormatters.money(12.50, currency: nil) == "12.5")
    }

    @Test func tokenTotalMatchesOfficialCountSemantics() {
        // 官方 total_tokens 口径 = input + output；input 已含缓存命中，reasoning 不计入。
        let usage = DailyTokenUsage(
            day: .now,
            input: 1_000_000,
            cachedInput: 800_000,
            cacheWriteInput: 50_000,
            output: 20_000,
            reasoning: 5_000
        )
        #expect(usage.total == 1_020_000)
    }

    @Test func filledHistoryIncludesZeroUsageDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5))!
        let activeDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3))!
        let history = [
            DailyTokenUsage(day: activeDay, totals: TokenTotals(input: 100, output: 20))
        ]

        let filled = DailyTokenUsage.filledHistory(
            from: history,
            endingAt: end,
            dayCount: 3,
            calendar: calendar
        )

        #expect(filled.map(\.id) == ["2026-08-03", "2026-08-04", "2026-08-05"])
        #expect(filled.map(\.total) == [120, 0, 0])
    }

    @Test func routePresentationCoversAllFourCombinations() {
        let combinations: [(CodexRoute, ClaudeRoute, QuotaPresentationPolicy.Mode, QuotaPresentationPolicy.Mode)] = [
            (.official, .official, .officialQuota, .officialQuota),
            (.official, .deepseek, .officialQuota, .sharedBalance),
            (.deepseek, .official, .sharedBalance, .officialQuota),
            (.deepseek, .deepseek, .sharedBalance, .sharedBalance)
        ]

        for (codex, claude, codexMode, claudeMode) in combinations {
            #expect(QuotaPresentationPolicy.mode(for: codex) == codexMode)
            #expect(QuotaPresentationPolicy.mode(for: claude) == claudeMode)
        }
        #expect(QuotaPresentationPolicy.mode(for: CodexRoute.unknown) == .unavailable)
        #expect(QuotaPresentationPolicy.mode(for: ClaudeRoute.unknown) == .unavailable)
    }

    @Test func calendarHeatmapAlignsDatesToMondayBasedGrid() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2025, month: 8, day: 12))! // Tuesday
        let end = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11))!
        let layout = CalendarHeatmapLayout(start: start, end: end, calendar: calendar)

        #expect(layout.leadingOffset == 1)
        #expect(CalendarHeatmapLayout.cell(forDayAt: 0, leadingOffset: layout.leadingOffset) == .init(column: 0, row: 1))
        #expect(CalendarHeatmapLayout.cell(forDayAt: 364, leadingOffset: layout.leadingOffset) == .init(column: 52, row: 1))
        #expect(layout.months.count == 12)
        #expect(layout.months.first?.column == 3) // September begins in the fourth displayed week.
        #expect(layout.months.last?.column == 50)
    }

    @Test func chartTooltipPlacementFollowsBarsAndStaysInsideEdges() {
        let container = CGSize(width: 300, height: 180)
        let tooltip = CGSize(width: 100, height: 80)
        let leftBar = CGRect(x: 40, y: 60, width: 20, height: 100)
        let rightBar = CGRect(x: 260, y: 20, width: 20, height: 140)

        let leftPlacement = ChartTooltipPlacement.adjacentToBar(
            barRect: leftBar,
            tooltipSize: tooltip,
            containerSize: container
        )
        let rightPlacement = ChartTooltipPlacement.adjacentToBar(
            barRect: rightBar,
            tooltipSize: tooltip,
            containerSize: container
        )
        #expect(leftPlacement.x > leftBar.maxX)
        #expect(rightPlacement.x < rightBar.minX)
        #expect(leftPlacement.y == 100)
        #expect(rightPlacement.y >= ChartTooltipPlacement.edgeInset + tooltip.height / 2)
    }

    @Test func keychainAccountMatchesCodexCLIStorageKey() {
        let home = URL(fileURLWithPath: "/tmp/codex-auth-test", isDirectory: true)
        #expect(CodexAuthStore.keychainAccount(for: home) == "cli|653a6cda303ad45d")
    }

    @Test func jsonlReaderHandlesChunkBoundariesAndFinalLine() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quotamonitor-jsonl-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"a\":1}\n{\"b\":\"跨块内容\"}\n{\"c\":3}".utf8).write(to: url)

        var lines: [String] = []
        let success = JSONLReader.forEachLine(at: url, chunkSize: 7) {
            lines.append(String(decoding: $0, as: UTF8.self))
        }

        #expect(success)
        #expect(lines == ["{\"a\":1}", "{\"b\":\"跨块内容\"}", "{\"c\":3}"])
    }
}
