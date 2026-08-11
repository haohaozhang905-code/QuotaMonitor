import AppKit
import SwiftUI
import XCTest
@testable import QuotaMonitor

final class BrandIconRenderTests: XCTestCase {
    /// 渲染菜单栏双槽位视图，便于核对槽位宽度与内容。
    @MainActor
    func testRenderMenuBarSlots() throws {
        let view = MenuBarSlotsView(
            codexRoute: .deepseek,
            claudeRoute: .unknown,
            codexRemaining: nil,
            claudeRemaining: nil,
            balanceAmount: 20.9,
            balanceCurrency: "CNY"
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = renderer.nsImage
        XCTAssertNotNil(image)
        guard let image else { return }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            XCTFail("menubar slots PNG 编码失败")
            return
        }
        try data.write(to: URL(fileURLWithPath: "/tmp/menubar-slots.png"))
    }

    /// 渲染各品牌图标为 PNG（便于人工核对），同时断言输出非空、非全透明。
    @MainActor
    func testRenderBrandIconsToPNG() throws {
        let kinds: [BrandIconKind] = [.codex, .claude, .claudeCode, .deepSeek, .workBuddy]
        for kind in kinds {
            let renderer = ImageRenderer(
                content: BrandIconView(kind: kind, size: 128)
                    .frame(width: 128, height: 128)
                    .background(Color.white)
            )
            renderer.scale = 1
            let image = renderer.nsImage
            XCTAssertNotNil(image, "\(kind) 渲染失败")
            guard let image else { continue }

            let url = URL(fileURLWithPath: "/tmp/brand-\(kind.rawValue).png")
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let data = rep.representation(using: .png, properties: [:]) else {
                XCTFail("\(kind) PNG 编码失败")
                continue
            }
            try data.write(to: url)

            // 非空白校验：彩色像素占比应显著（图标不是纯白/透明）。
            let bitmap = NSBitmapImageRep(data: data)!
            var colored = 0
            var total = 0
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                    guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                    total += 1
                    let r = color.redComponent
                    let g = color.greenComponent
                    let b = color.blueComponent
                    if max(r, g, b) - min(r, g, b) > 0.05 || max(r, g, b) < 0.97 {
                        colored += 1
                    }
                }
            }
            XCTAssertGreaterThan(total, 0)
            XCTAssertGreaterThan(
                Double(colored) / Double(total),
                kind == .workBuddy ? 0.35 : 0.15,
                "\(kind) 图标渲染过淡"
            )
        }
    }

    @MainActor
    func testRenderYearHeatmapToPNG() throws {
        let levels = (0..<365).map { index in index % 11 == 0 ? 4 : (index % 5) }
        for (name, scheme, background) in [
            ("light", ColorScheme.light, Color.white),
            ("dark", ColorScheme.dark, Color(nsColor: .windowBackgroundColor))
        ] {
            let renderer = ImageRenderer(
                content: TokenYearHeatmap(levels: levels, leadingOffset: 1)
                    .frame(width: 690, height: 81)
                    .padding(8)
                    .background(background)
                    .environment(\.colorScheme, scheme)
            )
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let data = rep.representation(using: .png, properties: [:]) else {
                XCTFail("365 天热力图 PNG 编码失败：\(name)")
                continue
            }
            try data.write(to: URL(fileURLWithPath: "/tmp/token-year-heatmap-\(name).png"))
            XCTAssertGreaterThan(rep.pixelsWide, 1_300)
            XCTAssertGreaterThan(rep.pixelsHigh, 150)
        }
    }
}
