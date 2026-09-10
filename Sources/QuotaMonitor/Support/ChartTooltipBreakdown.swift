import Foundation

struct ChartTooltipBreakdownEntry: Equatable, Sendable {
    let id: String
    let label: String
    let value: Int
    let hiddenItemCount: Int

    init(id: String, label: String, value: Int, hiddenItemCount: Int = 0) {
        self.id = id
        self.label = label
        self.value = value
        self.hiddenItemCount = hiddenItemCount
    }
}

enum ChartTooltipBreakdown {
    static func compact(
        _ entries: [ChartTooltipBreakdownEntry],
        visibleLimit: Int = 5
    ) -> [ChartTooltipBreakdownEntry] {
        let sorted = entries.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
        let limit = max(visibleLimit, 0)
        guard sorted.count > limit else { return sorted }
        let visible = Array(sorted.prefix(limit))
        let remainder = sorted.dropFirst(limit)
        return visible + [
            .init(
                id: "__other__",
                label: "",
                value: remainder.reduce(0) { $0 + $1.value },
                hiddenItemCount: remainder.count
            )
        ]
    }
}
