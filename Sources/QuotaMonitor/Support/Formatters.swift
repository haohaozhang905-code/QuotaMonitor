import Foundation

enum QuotaFormatters {
    static func reset(language: AppLanguage) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = language == .simplifiedChinese ? "M月d日 HH:mm" : "MMM d, HH:mm"
        return formatter
    }

    static func clock(language: AppLanguage) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    static func shortDate(language: AppLanguage) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = language == .simplifiedChinese ? "M/d" : "MMM d"
        return formatter
    }

    static func percent(_ remaining: Double?) -> String {
        guard let remaining else { return "--" }
        return "\(Int((remaining * 100).rounded()))%"
    }

    /// 把 token 数压缩成易读形式：1234 -> 1.2K，1234567 -> 1.2M。
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", value / 1_000) }
        return "\(count)"
    }

    /// 千分位 + k：1234567 -> "1,235k"；小于 1000 直接显示数字。
    static func tokensGrouped(_ count: Int) -> String {
        guard count >= 1_000 else { return "\(count)" }
        let thousands = Int((Double(count) / 1_000).rounded())
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return (formatter.string(from: NSNumber(value: thousands)) ?? "\(thousands)") + "k"
    }

    /// 中文单位（设计规范 v2）：>=1 亿用 "x.xx亿"，>=100 万用整数 "xxxx万"，
    /// 其余用一位小数 "x.x万"（去尾零），小于 1 万直接显示数字。
    static func tokensCN(_ count: Int) -> String {
        let value = Double(count)
        if value >= 100_000_000 {
            return trimmed(String(format: "%.2f", value / 100_000_000)) + "亿"
        }
        if value >= 10_000 {
            let wan = value / 10_000
            if wan >= 100 {
                return String(format: "%.0f", wan) + "万"
            }
            return trimmed(String(format: "%.1f", wan)) + "万"
        }
        return "\(count)"
    }

    private static func trimmed(_ text: String) -> String {
        text.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    /// 把金额格式化为可读字符串：12.26 -> "12.26"，12.00 -> "12"；CNY 带 ¥ 前缀。
    static func money(_ value: Double, currency: String?) -> String {
        let symbol = currency?.uppercased() == "CNY" ? "¥" : ""
        let formatted = String(format: "%.2f", value)
        let trimmed = formatted.replacingOccurrences(
            of: #"\.?0+$"#,
            with: "",
            options: .regularExpression
        )
        return "\(symbol)\(trimmed)"
    }

    @MainActor static func relativeReset(from date: Date, language: LanguageSettings, now: Date = .now) -> String {
        let seconds = max(date.timeIntervalSince(now), 0)
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours >= 24 { return language.text("time.daysHours", hours / 24, hours % 24) }
        if hours > 0 { return language.text("time.hoursMinutes", hours, minutes) }
        return language.text("time.minutes", minutes)
    }
}
