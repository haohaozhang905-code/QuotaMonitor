import CoreGraphics
import XCTest
@testable import QuotaMonitor

final class SVGPathTests: XCTestCase {
    /// 各品牌图标解析后应落在对应的视框内，且形状非空。
    func testBrandPathsParseToSaneBounds() {
        // workBuddy 的 W 路径在官方文件里超出 40×40 视框，由方形容器裁剪，
        // 因此单独放宽边界校验。
        let cases: [(String, String, CGFloat, CGFloat, CGFloat)] = [
            ("codex", BrandIconPaths.codex, 0, 24, 1),
            ("claude", BrandIconPaths.claude, 0, 24, 1),
            ("claudeCode", BrandIconPaths.claudeCode, 0, 24, 1),
            ("deepSeek", BrandIconPaths.deepSeek, 0, 24, 1),
            ("workBuddy", BrandIconPaths.workBuddy, 0, 40, 7),
        ]

        for (name, d, expectedMin, expectedMax, tolerance) in cases {
            let path = SVGPath.cgPath(from: d)
            let box = path.boundingBoxOfPath
            XCTAssertFalse(box.isEmpty, "\(name) 路径不应为空")
            XCTAssertLessThan(box.minX, expectedMax, "\(name) minX 越界")
            XCTAssertLessThan(box.minY, expectedMax, "\(name) minY 越界")
            XCTAssertGreaterThan(box.maxX, expectedMin, "\(name) maxX 越界")
            XCTAssertGreaterThan(box.maxY, expectedMin, "\(name) maxY 越界")
            XCTAssertLessThanOrEqual(box.maxX, expectedMax + tolerance, "\(name) maxX 超视框")
            XCTAssertLessThanOrEqual(box.maxY, expectedMax + tolerance, "\(name) maxY 超视框")
            XCTAssertGreaterThan(box.width, 0.5, "\(name) 应有实际宽度")
            XCTAssertGreaterThan(box.height, 0.5, "\(name) 应有实际高度")
        }
    }

    /// 已知简单路径：矩形应解析出四个顶点。
    func testSimplePath() {
        let path = SVGPath.cgPath(from: "M0 0 H10 V10 H0 Z")
        XCTAssertEqual(path.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    /// 相对坐标与省略重复指令（如 `l` 后跟两组点）应正确展开。
    func testRelativeImplicitRepetition() {
        // 从 (1,1) 出发，相对 l(2,0) l(0,2) l(-2,0) 构成三角形。
        let path = SVGPath.cgPath(from: "M1 1l2 0 0 2-2 0z")
        let box = path.boundingBoxOfPath
        XCTAssertEqual(box, CGRect(x: 1, y: 1, width: 2, height: 2))
    }

    /// 弧线命令应产生曲线而非直线。
    func testArcProducesCurve() {
        // 半圆弧：起点 (0,0) 终点 (4,0)，半径 2，sweep=1。
        let path = SVGPath.cgPath(from: "M0 0 A2 2 0 0 1 4 0")
        let box = path.boundingBoxOfPath
        XCTAssertGreaterThan(box.height, 0.5, "弧线应有弓高")
        XCTAssertEqual(box.minX, 0, accuracy: 0.01)
        XCTAssertEqual(box.maxX, 4, accuracy: 0.01)
    }
}
