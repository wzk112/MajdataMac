import Foundation

public enum ChartTransform: String, CaseIterable, Sendable {
    case mirrorHorizontal = "左右镜像", mirrorVertical = "上下镜像", rotateHalf = "旋转 180°", rotateClockwise = "顺时针 45°", rotateCounterclockwise = "逆时针 45°"

    public func apply(to source: String) -> String {
        if self == .rotateHalf { return ChartTransform.mirrorVertical.apply(to: ChartTransform.mirrorHorizontal.apply(to: source)) }
        let a = Array(source)
        var output = "", i = 0, previous: Character = " ", segmentStart = 1
        func mapLane(_ n: Int, special: Bool) -> Int {
            switch self {
            case .mirrorHorizontal: return special ? (9 - n) % 8 + 1 : 9 - n
            case .mirrorVertical: return special ? (13 - n) % 8 + 1 : (12 - n) % 8 + 1
            case .rotateClockwise: return n % 8 + 1
            case .rotateCounterclockwise: return (n + 6) % 8 + 1
            case .rotateHalf: return (n + 3) % 8 + 1
            }
        }
        while i < a.count {
            let c = a[i]
            if c == "|", i + 1 < a.count, a[i + 1] == "|" {
                while i < a.count && a[i] != "\n" { output.append(a[i]); i += 1 }; continue
            }
            if c == "(" || c == "{" || c == "[" || (c == "<" && String(a[i..<min(i + 4, a.count)]) == "<HS*") {
                let end: Character = c == "(" ? ")" : (c == "{" ? "}" : (c == "[" ? "]" : ">"))
                repeat { output.append(a[i]); i += 1 } while i < a.count && a[i - 1] != end
                continue
            }
            if let n = c.wholeNumberValue, (1...8).contains(n) {
                output += String(mapLane(n, special: previous == "D" || previous == "E"))
                segmentStart = n
            } else if c == "<" || c == ">" {
                let upperBefore = [1, 2, 7, 8].contains(segmentStart)
                let upperAfter = [1, 2, 7, 8].contains(mapLane(segmentStart, special: false))
                let reflection = self == .mirrorHorizontal || self == .mirrorVertical
                let swap = (upperBefore != upperAfter) != reflection
                output.append(swap ? (c == "<" ? ">" : "<") : c)
            } else if (self == .mirrorHorizontal || self == .mirrorVertical), let swapped = ["p": "q", "q": "p", "s": "z", "z": "s"][String(c)] { output += swapped }
            else { output.append(c) }
            if !c.isWhitespace { previous = c }
            i += 1
        }
        return output
    }
    public static func subdivide(_ source: String, factor: Int) -> String {
        guard factor > 0 && factor <= 16 else { return source }
        let a = Array(source); var i = 0, output = ""
        while i < a.count {
            if a[i] == "|", i + 1 < a.count, a[i + 1] == "|" {
                while i < a.count && a[i] != "\n" { output.append(a[i]); i += 1 }; continue
            }
            if a[i] == "{" {
                var j = i + 1
                while j < a.count && a[j] != "}" { j += 1 }
                guard j < a.count else { output += String(a[i...]); break }
                let raw = String(a[(i + 1)..<j])
                if raw.hasPrefix("#"), let seconds = Double(raw.dropFirst()) { output += "{#\(seconds / Double(factor))}" }
                else if let n = Double(raw) { output += "{\((n * Double(factor)).formatted(.number.grouping(.never)))}" }
                else { output += String(a[i...j]) }
                i = j + 1; continue
            }
            output += a[i] == "," ? String(repeating: ",", count: factor) : String(a[i]); i += 1
        }
        return output
    }
}
