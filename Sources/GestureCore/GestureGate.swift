import Foundation
public struct GestureGate {
    public var holdDuration: Double = 1.0
    public var releaseDuration: Double = 0.65
    private var began: Double?
    private var released: Double?
    public private(set) var armed = true
    public private(set) var progress = 0.0
    private var lastTime: Double?
    public init() {}
    public mutating func update(isVictory: Bool, at time: Double) -> Bool {
        if let lastTime, time - lastTime > 0.5 || time < lastTime { began = nil; released = nil; progress = 0 }
        lastTime = time
        if !isVictory {
            began = nil; progress = 0
            if !armed {
                if released == nil { released = time }
                if time - released! >= releaseDuration { armed = true; released = nil }
            }
            return false
        }
        released = nil
        guard armed else { return false }
        if began == nil { began = time }
        progress = min(1, max(0, (time - began!) / holdDuration))
        if progress >= 1 { armed = false; began = nil; return true }
        return false
    }
    public mutating func interrupt() { began = nil; released = nil; progress = 0; lastTime = nil }
    public mutating func reset() { self = GestureGate() }
}
public struct HandPoint: Sendable {
    public var x: Double; public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public func distance(to p: HandPoint) -> Double { hypot(x-p.x, y-p.y) }
}
public enum VictoryClassifier {
    public static func matches(wrist: HandPoint, index: [HandPoint], middle: [HandPoint], ring: [HandPoint], little: [HandPoint]) -> Bool {
        guard [index,middle,ring,little].allSatisfy({ $0.count == 3 }) else { return false }
        func extended(_ f: [HandPoint]) -> Bool {
            let a = f[0], b = f[1], c = f[2]
            let ux = a.x-b.x, uy = a.y-b.y, vx = c.x-b.x, vy = c.y-b.y
            let d = hypot(ux,uy)*hypot(vx,vy)
            return d > 0.0001 && (ux*vx+uy*vy)/d < -0.65 && c.distance(to:wrist) > b.distance(to:wrist)*1.18
        }
        func folded(_ f: [HandPoint]) -> Bool { f[2].distance(to:wrist) < f[1].distance(to:wrist)*1.12 }
        let scale = index[0].distance(to:wrist)
        return scale > 0.02 && extended(index) && extended(middle) && folded(ring) && folded(little) && index[2].distance(to:middle[2]) > scale*0.30
    }
}
