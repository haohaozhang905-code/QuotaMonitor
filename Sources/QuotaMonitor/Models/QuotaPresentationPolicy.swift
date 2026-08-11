import Foundation

/// 把路由状态转换成界面应该展示的数据类型，避免额度与共享余额在不同组合下串用。
enum QuotaPresentationPolicy {
    enum Mode: Equatable {
        case officialQuota
        case sharedBalance
        case unavailable
    }

    static func mode(for route: CodexRoute) -> Mode {
        switch route {
        case .official: .officialQuota
        case .deepseek: .sharedBalance
        case .unknown: .unavailable
        }
    }

    static func mode(for route: ClaudeRoute) -> Mode {
        switch route {
        case .official: .officialQuota
        case .deepseek: .sharedBalance
        case .unknown: .unavailable
        }
    }
}

/// 365 天日历使用周一为首列的真实日期布局。
struct CalendarHeatmapLayout {
    struct MonthMarker: Identifiable, Equatable {
        let date: Date
        let column: Int

        var id: Date { date }
    }

    struct Cell: Equatable {
        let column: Int
        let row: Int
    }

    let leadingOffset: Int
    let months: [MonthMarker]

    init(start: Date, end: Date, calendar: Calendar = .current) {
        leadingOffset = (calendar.component(.weekday, from: start) + 5) % 7

        var components = calendar.dateComponents([.year, .month], from: start)
        components.day = 1
        var month = calendar.date(from: components) ?? start
        if month < start {
            month = calendar.date(byAdding: .month, value: 1, to: month) ?? month
        }

        var markers: [MonthMarker] = []
        while month <= end {
            let dayOffset = calendar.dateComponents([.day], from: start, to: month).day ?? 0
            markers.append(MonthMarker(
                date: month,
                column: (leadingOffset + max(dayOffset, 0)) / 7
            ))
            guard let next = calendar.date(byAdding: .month, value: 1, to: month), next > month else { break }
            month = next
        }
        months = markers
    }

    static func cell(forDayAt index: Int, leadingOffset: Int) -> Cell {
        let cellIndex = leadingOffset + index
        return Cell(column: cellIndex / 7, row: cellIndex % 7)
    }
}
