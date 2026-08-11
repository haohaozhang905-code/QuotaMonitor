import CoreGraphics
import Foundation

/// 把 SVG path 的 `d` 字符串解析为 CGPath。
///
/// 支持 M/L/H/V/C/S/Q/T/A（含小写相对形式）与 Z，覆盖品牌图标路径用到的全部指令。
/// 弧线 flag 按 SVG 规范以单字符 0/1 解析（例如 `013.046` = flag 0 + 数字 13.046），
/// 弧线几何转成若干段三次贝塞尔。
enum SVGPath {
    static func cgPath(from d: String) -> CGPath {
        let path = CGMutablePath()
        var tokens = tokenize(d)
        guard !tokens.isEmpty else { return path }

        var index = 0
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastCommand: Character = " "
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?

        func number() -> CGFloat? {
            guard index < tokens.count, let raw = tokens[index] as? String, let value = Double(raw) else {
                return nil
            }
            index += 1
            return CGFloat(value)
        }

        /// 按 SVG flag 语法读取单个 0/1 字符；剩余数字串插回 token 流。
        func flag() -> Bool? {
            guard index < tokens.count, let raw = tokens[index] as? String,
                  let first = raw.first, first == "0" || first == "1" else {
                return nil
            }
            let rest = String(raw.dropFirst())
            if rest.isEmpty {
                index += 1
            } else {
                tokens[index] = rest
            }
            return first == "1"
        }

        func point() -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: x, y: y)
        }

        while index < tokens.count {
            guard let raw = tokens[index] as? String else { break }
            let command: Character
            if raw.count == 1, "MLHVCSQTAZmlhvcsqtaz".contains(raw) {
                command = raw[raw.startIndex]
                index += 1
            } else if lastCommand != " " {
                // 数字开头：省略重复指令，沿用上一命令（保留相对/绝对）。
                command = lastCommand
            } else {
                break
            }

            let isRelative = command.isLowercase
            let upper = Character(String(command).uppercased())

            func relative(_ value: CGFloat) -> CGFloat {
                isRelative ? current.x + value : value
            }
            func relativeY(_ value: CGFloat) -> CGFloat {
                isRelative ? current.y + value : value
            }
            func reflectedControl(previous: CGPoint) -> CGPoint {
                CGPoint(x: 2 * current.x - previous.x, y: 2 * current.y - previous.y)
            }

            switch upper {
            case "M":
                guard let p = point() else { index = tokens.count; break }
                current = CGPoint(x: relative(p.x), y: relativeY(p.y))
                start = current
                path.move(to: current)
                // M 后跟多个点时，后续点按 L 处理（保持相对/绝对）。
                lastCommand = isRelative ? "l" : "L"
            case "L":
                guard let p = point() else { index = tokens.count; break }
                current = CGPoint(x: relative(p.x), y: relativeY(p.y))
                path.addLine(to: current)
                lastCommand = command
            case "H":
                guard let value = number() else { index = tokens.count; break }
                current = CGPoint(x: relative(value), y: current.y)
                path.addLine(to: current)
                lastCommand = command
            case "V":
                guard let value = number() else { index = tokens.count; break }
                current = CGPoint(x: current.x, y: relativeY(value))
                path.addLine(to: current)
                lastCommand = command
            case "C":
                guard let c1 = point(), let c2 = point(), let end = point() else { index = tokens.count; break }
                let c1p = CGPoint(x: relative(c1.x), y: relativeY(c1.y))
                let c2p = CGPoint(x: relative(c2.x), y: relativeY(c2.y))
                let endp = CGPoint(x: relative(end.x), y: relativeY(end.y))
                path.addCurve(to: endp, control1: c1p, control2: c2p)
                current = endp
                lastCubicControl = c2p
                lastCommand = command
            case "S":
                guard let c2 = point(), let end = point() else { index = tokens.count; break }
                let c1p: CGPoint
                if let lastCubicControl, lastCommand == "C" || lastCommand == "S" {
                    c1p = reflectedControl(previous: lastCubicControl)
                } else {
                    c1p = current
                }
                let c2p = CGPoint(x: relative(c2.x), y: relativeY(c2.y))
                let endp = CGPoint(x: relative(end.x), y: relativeY(end.y))
                path.addCurve(to: endp, control1: c1p, control2: c2p)
                current = endp
                lastCubicControl = c2p
                lastCommand = command
            case "Q":
                guard let control = point(), let end = point() else { index = tokens.count; break }
                let controlP = CGPoint(x: relative(control.x), y: relativeY(control.y))
                let endp = CGPoint(x: relative(end.x), y: relativeY(end.y))
                path.addQuadCurve(to: endp, control: controlP)
                current = endp
                lastQuadControl = controlP
                lastCommand = command
            case "T":
                guard let end = point() else { index = tokens.count; break }
                let controlP: CGPoint
                if let lastQuadControl, lastCommand == "Q" || lastCommand == "T" {
                    controlP = reflectedControl(previous: lastQuadControl)
                } else {
                    controlP = current
                }
                let endp = CGPoint(x: relative(end.x), y: relativeY(end.y))
                path.addQuadCurve(to: endp, control: controlP)
                current = endp
                lastQuadControl = controlP
                lastCommand = command
            case "A":
                guard let rx = number(), let ry = number(), let rotation = number(),
                      let largeFlag = flag(), let sweepFlag = flag(), let end = point() else {
                    index = tokens.count
                    break
                }
                let endp = CGPoint(x: relative(end.x), y: relativeY(end.y))
                appendArc(
                    to: path,
                    from: current,
                    to: endp,
                    radiusX: abs(rx),
                    radiusY: abs(ry),
                    rotation: rotation,
                    largeArc: largeFlag,
                    sweep: sweepFlag
                )
                current = endp
                lastCommand = command
            case "Z":
                path.closeSubpath()
                current = start
                lastCubicControl = nil
                lastQuadControl = nil
                lastCommand = "Z"
            default:
                index = tokens.count
            }
        }
        return path
    }

    // MARK: - Tokenizer

    /// 命令字母（单字符字符串）与数字原文字符串交替的扁平数组。
    private static func tokenize(_ d: String) -> [String] {
        var result: [String] = []
        var buffer = ""

        func flushNumber() {
            guard !buffer.isEmpty else { return }
            result.append(buffer)
            buffer = ""
        }

        for scalar in d.unicodeScalars {
            let char = Character(scalar)
            if char.isNumber || char == "e" || char == "E" {
                buffer.append(char)
            } else if char == "." {
                // SVG 紧凑写法允许 "1.891.54"（两个数连续出现），遇到第二个小数点先落盘。
                if buffer.contains(".") {
                    flushNumber()
                }
                buffer.append(char)
            } else if char == "-" || char == "+" {
                // 符号：若缓冲区已有完整数字（非指数尾），说明上一个数字已结束。
                if buffer.isEmpty || buffer.hasSuffix("e") || buffer.hasSuffix("E") {
                    buffer.append(char)
                } else {
                    flushNumber()
                    buffer.append(char)
                }
            } else if char.isWhitespace || char == "," {
                flushNumber()
            } else if "MLHVCSQTAZmlhvcsqtaz".contains(char) {
                flushNumber()
                result.append(String(char))
            } else {
                flushNumber()
            }
        }
        flushNumber()
        return result
    }

    // MARK: - Arc → Cubic Bézier

    private static func appendArc(
        to path: CGMutablePath,
        from start: CGPoint,
        to end: CGPoint,
        radiusX: CGFloat,
        radiusY: CGFloat,
        rotation: CGFloat,
        largeArc: Bool,
        sweep: Bool
    ) {
        guard radiusX > 0, radiusY > 0, start != end else {
            path.addLine(to: end)
            return
        }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        var rx = abs(radiusX)
        var ry = abs(radiusY)
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
        }

        let rx2 = rx * rx
        let ry2 = ry * ry
        let numerator = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
        let denominator = rx2 * y1p * y1p + ry2 * x1p * x1p
        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let coef = numerator > 0 ? sign * sqrt(max(numerator / denominator, 0)) : 0
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * (-ry * x1p / rx)

        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat) -> CGFloat {
            atan2(uy, ux)
        }
        func vectorAngle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var angle = acos(max(-1, min(1, dot / max(len, 0.000001))))
            if ux * vy - uy * vx < 0 { angle = -angle }
            return angle
        }

        let ux = (x1p - cxp) / rx
        let uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx
        let vy = (-y1p - cyp) / ry
        let theta1 = angle(ux, uy)
        var deltaTheta = vectorAngle(ux, uy, vx, vy)

        if !sweep, deltaTheta > 0 { deltaTheta -= 2 * .pi }
        if sweep, deltaTheta < 0 { deltaTheta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(deltaTheta) / (.pi / 2))))
        let segmentAngle = deltaTheta / CGFloat(segments)
        let alpha = 4 / 3 * tan(segmentAngle / 4)

        var currentPoint = start
        var theta = theta1
        for _ in 0..<segments {
            let theta2 = theta + segmentAngle
            let cosT1 = cos(theta)
            let sinT1 = sin(theta)
            let cosT2 = cos(theta2)
            let sinT2 = sin(theta2)

            let p2 = CGPoint(
                x: cx + rx * cosT2 * cosPhi - ry * sinT2 * sinPhi,
                y: cy + rx * cosT2 * sinPhi + ry * sinT2 * cosPhi
            )
            let c1 = CGPoint(
                x: currentPoint.x + alpha * (-rx * sinT1 * cosPhi - ry * cosT1 * sinPhi),
                y: currentPoint.y + alpha * (-rx * sinT1 * sinPhi + ry * cosT1 * cosPhi)
            )
            let c2 = CGPoint(
                x: p2.x + alpha * (rx * sinT2 * cosPhi + ry * cosT2 * sinPhi),
                y: p2.y + alpha * (rx * sinT2 * sinPhi - ry * cosT2 * cosPhi)
            )
            path.addCurve(to: p2, control1: c1, control2: c2)
            currentPoint = p2
            theta = theta2
        }
    }
}
