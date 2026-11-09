import Foundation
import CoreFoundation

enum CacheExclusionReason: String, Codable, Hashable, CaseIterable, Sendable {
    case unsupportedSource, unsupportedFormat, missingFields, invalidFields
    case missingTime, oldCache, fileUnreadable, sourceUnavailable
    var localizationKey: String { "cache.reason." + rawValue }
}

func cacheEvidenceInteger(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    return Int(number.stringValue)
}

/// Cache counts are only eligible when the source explicitly supplies enough
/// information to distinguish a missing field from an observed zero.
struct CacheUsageMeasurement: Codable, Equatable, Sendable {
    let input: Int
    let cachedInput: Int
    let cacheWriteInput: Int?
    let total: Int

    init?(input: Int?, cachedInput: Int?, cacheWriteInput: Int?, output: Int?) {
        guard let input, let cachedInput, let output,
              input >= 0, cachedInput >= 0, output >= 0,
              cachedInput <= input else { return nil }
        if let cacheWriteInput {
            guard cacheWriteInput >= 0, cacheWriteInput <= input - cachedInput else { return nil }
        }
        let (total, overflow) = input.addingReportingOverflow(output)
        guard !overflow else { return nil }
        self.input = input
        self.cachedInput = cachedInput
        self.cacheWriteInput = cacheWriteInput
        self.total = total
    }

    func adding(_ other: Self) -> Self? {
        let (input, inputOverflow) = input.addingReportingOverflow(other.input)
        let (cached, cachedOverflow) = cachedInput.addingReportingOverflow(other.cachedInput)
        let (total, totalOverflow) = total.addingReportingOverflow(other.total)
        guard !inputOverflow, !cachedOverflow, !totalOverflow, total >= input else { return nil }
        let write: Int?
        if let left = cacheWriteInput, let right = other.cacheWriteInput {
            let (sum, overflow) = left.addingReportingOverflow(right)
            guard !overflow else { return nil }
            write = sum
        } else { write = nil }
        return Self(input: input, cachedInput: cached, cacheWriteInput: write, output: total - input)
    }

    func subtracting(_ previous: Self) -> Self? {
        guard input >= previous.input, cachedInput >= previous.cachedInput,
              total >= previous.total else { return nil }
        let input = input - previous.input
        let total = total - previous.total
        guard total >= input else { return nil }
        let write: Int?
        if let current = cacheWriteInput, let earlier = previous.cacheWriteInput {
            guard current >= earlier else { return nil }
            write = current - earlier
        } else if cacheWriteInput == nil && previous.cacheWriteInput == nil {
            write = nil
        } else { return nil }
        return Self(input: input, cachedInput: cachedInput - previous.cachedInput,
                    cacheWriteInput: write, output: total - input)
    }
}

struct CacheUsageSummary: Equatable, Sendable {
    let eligibleInput: Int
    let cachedInput: Int
    let coveredTokens: Int
    let observedTokens: Int

    init?(measurements: [CacheUsageMeasurement], observedTokens: Int) {
        guard observedTokens >= 0 else { return nil }
        var input = 0, cached = 0, covered = 0
        for item in measurements {
            let (nextInput, inputOverflow) = input.addingReportingOverflow(item.input)
            let (nextCached, cachedOverflow) = cached.addingReportingOverflow(item.cachedInput)
            let (nextCovered, coveredOverflow) = covered.addingReportingOverflow(item.total)
            guard !inputOverflow, !cachedOverflow, !coveredOverflow else { return nil }
            input = nextInput
            cached = nextCached
            covered = nextCovered
        }
        guard covered <= observedTokens else { return nil }
        self.eligibleInput = input
        self.cachedInput = cached
        self.coveredTokens = covered
        self.observedTokens = observedTokens
    }

    var hitRate: Double? {
        eligibleInput > 0 ? Double(cachedInput) / Double(eligibleInput) : nil
    }

    var coverage: Double? {
        observedTokens > 0 ? Double(coveredTokens) / Double(observedTokens) : nil
    }

    var isPartial: Bool { coveredTokens < observedTokens }

    static func percentage(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value == 0 { return "0%" }
        if value == 1 { return "100%" }
        if value < 0.001 { return "<0.1%" }
        if value > 0.999 { return ">99.9%" }
        return String(format: "%.1f%%", value * 100)
    }

    /// Fraction of the existing total-token bar, not fraction of input.
    static func barFraction(cachedInput: Int, rowTotal: Int) -> Double? {
        guard rowTotal > 0, cachedInput >= 0, cachedInput <= rowTotal else { return nil }
        return Double(cachedInput) / Double(rowTotal)
    }
}
