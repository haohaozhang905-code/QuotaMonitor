import Foundation
import Testing
@testable import QuotaMonitor

struct CacheUsageMeasurementTests {
    @Test func weightedRateCoverageAndBarUseDifferentDenominators() throws {
        let first = try #require(CacheUsageMeasurement(input: 100, cachedInput: 90, cacheWriteInput: 0, output: 10))
        let second = try #require(CacheUsageMeasurement(input: 900, cachedInput: 10, cacheWriteInput: 0, output: 90))
        let summary = try #require(CacheUsageSummary(measurements: [first, second], observedTokens: 1_375))
        #expect(summary.hitRate == 0.1)
        #expect(summary.coverage == 0.8)
        #expect(CacheUsageSummary.barFraction(cachedInput: 80, rowTotal: 200) == 0.4)
    }

    @Test func missingInvalidAndObservedZeroRemainDistinct() throws {
        #expect(CacheUsageMeasurement(input: 100, cachedInput: nil, cacheWriteInput: nil, output: 0) == nil)
        #expect(CacheUsageMeasurement(input: 100, cachedInput: 101, cacheWriteInput: nil, output: 0) == nil)
        #expect(CacheUsageMeasurement(input: 100, cachedInput: 80, cacheWriteInput: 21, output: 0) == nil)
        let zero = try #require(CacheUsageMeasurement(input: 100, cachedInput: 0, cacheWriteInput: nil, output: 0))
        #expect(CacheUsageSummary(measurements: [zero], observedTokens: 100)?.hitRate == 0)
        let noInput = try #require(CacheUsageMeasurement(input: 0, cachedInput: 0, cacheWriteInput: nil, output: 1))
        #expect(CacheUsageSummary(measurements: [noInput], observedTokens: 1)?.hitRate == nil)
        #expect(CacheUsageSummary(measurements: [zero], observedTokens: 99) == nil)
        #expect(CacheUsageSummary.percentage(0.00001) == "<0.1%")
        #expect(CacheUsageSummary.percentage(0.99999) == ">99.9%")
        #expect(CacheUsageSummary.percentage(0) == "0%")
        #expect(CacheUsageSummary.percentage(1) == "100%")
    }

    @Test func cumulativeEvidenceRequiresBothBoundaries() throws {
        let first = TokenTotals(input: 100, cachedInput: 80, output: 20,
                                cacheMeasurement: CacheUsageMeasurement(input: 100, cachedInput: 80, cacheWriteInput: nil, output: 20))
        let missing = TokenTotals(input: 150, cachedInput: 80, output: 30)
        let next = TokenTotals(input: 200, cachedInput: 170, output: 40,
                               cacheMeasurement: CacheUsageMeasurement(input: 200, cachedInput: 170, cacheWriteInput: nil, output: 40))
        #expect(next.subtracting(missing).cacheMeasurement == nil)
        #expect(next.subtracting(first).cacheMeasurement?.cachedInput == 90)
        #expect(first.subtracting(next).cacheMeasurement == nil)
        #expect(first.adding(missing).cacheMeasurement?.total == 120)
    }

    @Test func legacyTotalsDecodeWithoutInventingCacheEvidence() throws {
        let old = Data(#"{"input":100,"cachedInput":0,"cacheWriteInput":0,"output":20,"reasoning":0}"#.utf8)
        let totals = try JSONDecoder().decode(TokenTotals.self, from: old)
        #expect(totals.input == 100)
        #expect(totals.cacheMeasurement == nil)
    }

    @Test func evidenceAcceptsOnlyIntegerTokenFields() {
        #expect(cacheEvidenceInteger(NSNumber(value: true)) == nil)
        #expect(cacheEvidenceInteger(NSNumber(value: 2.5)) == nil)
        #expect(cacheEvidenceInteger(NSNumber(value: 0)) == 0)
        #expect(cacheEvidenceInteger("100") == nil)
    }
}
