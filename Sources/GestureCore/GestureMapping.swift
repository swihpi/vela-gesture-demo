import Foundation

public enum GestureKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case victory, openPalm, fist, thumbsUp
    public var id: String { rawValue }
    public var title: String { switch self { case .victory: "V sign"; case .openPalm: "Open palm"; case .fist: "Closed fist"; case .thumbsUp: "Thumbs up" } }
    public var glyph: String { switch self { case .victory: "✌︎"; case .openPalm: "✋︎"; case .fist: "✊︎"; case .thumbsUp: "👍︎" } }
    public var instruction: String { switch self { case .victory: "Extend index and middle fingers"; case .openPalm: "Face your palm forward; extend four long fingers"; case .fist: "Close all fingers into a fist"; case .thumbsUp: "Close four fingers and point your thumb up" } }
}
public enum ZoomAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case toggleVideo, videoOff, videoOn, mute, unmute, toggleMicrophone, toggleRecording
    public var id: String { rawValue }
    public var title: String { switch self { case .toggleVideo: "Toggle video"; case .videoOff: "Turn video off"; case .videoOn: "Turn video on"; case .mute: "Mute microphone"; case .unmute: "Unmute microphone"; case .toggleMicrophone: "Toggle microphone"; case .toggleRecording: "Start / stop recording" } }
    public var isRecording: Bool { self == .toggleRecording }
    public var isVideo: Bool { [.toggleVideo,.videoOff,.videoOn].contains(self) }
    /// nil means toggle. Explicit actions must never fall back to a blind toggle.
    public var desiredState: Bool? { switch self { case .videoOn,.unmute: true; case .videoOff,.mute: false; default: nil } }
    public func target(from current: Bool) -> Bool { desiredState ?? !current }
}
public struct GestureMapping: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var gesture: GestureKind
    public var action: ZoomAction
    public var hold: Double
    public var enabled: Bool
    public init(id: UUID = UUID(), gesture: GestureKind, action: ZoomAction, hold: Double = 1, enabled: Bool = true) { self.id=id; self.gesture=gesture; self.action=action; self.hold=hold; self.enabled=enabled }
    public static var defaults: [GestureMapping] { [.init(gesture:.victory,action:.toggleVideo),.init(gesture:.openPalm,action:.toggleVideo),.init(gesture:.fist,action:.toggleRecording,hold:1.5),.init(gesture:.thumbsUp,action:.toggleMicrophone,hold:1.3)] }
    public static func validationError(_ mappings: [GestureMapping]) -> String? {
        guard Set(mappings.map(\.id)).count == mappings.count else { return "Duplicate mapping identifiers" }
        guard mappings.allSatisfy({ $0.hold.isFinite && (0.5...3).contains($0.hold) }) else { return "Hold duration must be 0.5–3 seconds" }
        let active = mappings.filter(\.enabled).map(\.gesture)
        guard Set(active).count == active.count else { return "Each gesture can have only one enabled mapping" }
        return nil
    }
}

/// One shared latch prevents changing directly from one mapped pose to another
/// from firing multiple commands. Only a neutral pose (or no hand) releases it.
public struct MappingGate {
    private var candidate: GestureKind?
    private var began: Double?
    private var released: Double?
    private var lastTime: Double?
    private var uncertainBegan: Double?
    public private(set) var armed: Bool
    public private(set) var progress = 0.0
    public init(requireNeutral: Bool = false) { armed = !requireNeutral }
    public mutating func interrupt() { candidate=nil; began=nil; released=nil; lastTime=nil; uncertainBegan=nil; progress=0 }
    /// Brief low-confidence tracking freezes the hold instead of restarting it.
    /// It can never release the latch or generate an action by itself.
    public mutating func uncertain(at time: Double) {
        if let lastTime, time-lastTime > 0.5 || time < lastTime { interrupt() }
        lastTime=time; released=nil
        if uncertainBegan == nil { uncertainBegan=time }
        if time-uncertainBegan! > 0.25 { candidate=nil; began=nil; progress=0 }
    }
    public mutating func update(_ gesture: GestureKind?, at time: Double, hold: Double) -> GestureKind? {
        if let lastTime, time < lastTime || time-lastTime > 0.5 { interrupt() }
        lastTime=time
        if let lost=uncertainBegan {
            if time-lost > 0.25 { candidate=nil; began=nil; progress=0 }
            else if let started=began { began=started+(time-lost) }
            uncertainBegan=nil
        }
        guard let gesture else {
            candidate=nil; began=nil; progress=0
            if !armed {
                if released == nil { released=time }
                if time-released! >= 0.65 { armed=true; released=nil }
            }
            return nil
        }
        released=nil
        guard armed else { return nil }
        if candidate != gesture { candidate=gesture; began=time; progress=0 }
        if began == nil { began=time }
        progress=min(1,max(0,(time-began!)/max(hold,0.5)))
        if progress >= 1 { armed=false; began=nil; candidate=nil; return gesture }
        return nil
    }
}

public struct HandPose: Sendable {
    public var wrist: HandPoint
    /// MCP, PIP (IP for thumb), tip.
    public var thumb, index, middle, ring, little: [HandPoint]
    public init(wrist: HandPoint, thumb: [HandPoint], index: [HandPoint], middle: [HandPoint], ring: [HandPoint], little: [HandPoint]) { self.wrist=wrist; self.thumb=thumb; self.index=index; self.middle=middle; self.ring=ring; self.little=little }
    private func extended(_ f: [HandPoint]) -> Bool {
        let a=f[0], b=f[1], c=f[2]
        let ux=a.x-b.x, uy=a.y-b.y, vx=c.x-b.x, vy=c.y-b.y
        let d=hypot(ux,uy)*hypot(vx,vy)
        return d > 0.0001 && (ux*vx+uy*vy)/d < -0.65 && c.distance(to:wrist) > b.distance(to:wrist)*1.18
    }
    private func folded(_ f: [HandPoint]) -> Bool { f[2].distance(to:wrist) < f[1].distance(to:wrist)*1.12 }
    public var diagnosticDescription: String {
        guard [thumb,index,middle,ring,little].allSatisfy({ $0.count==3 }) else { return "incomplete hand" }
        let fingers=[("index",index),("middle",middle),("ring",ring),("little",little)]
        return fingers.map { name,f in
            let a=f[0],b=f[1],c=f[2],ux=a.x-b.x,uy=a.y-b.y,vx=c.x-b.x,vy=c.y-b.y
            let cosine=(ux*vx+uy*vy)/max(0.0001,hypot(ux,uy)*hypot(vx,vy))
            return String(format:"%@ ratio=%.2f angleCos=%.2f",name,c.distance(to:wrist)/max(0.001,b.distance(to:wrist)),cosine)
        }.joined(separator:"; ")+String(format:"; thumbSpread=%.2f",thumb[2].distance(to:index[0])/max(0.001,index[0].distance(to:wrist)))
    }
    public func classify() -> GestureKind? {
        guard [thumb,index,middle,ring,little].allSatisfy({ $0.count==3 }) else { return nil }
        let scale=index[0].distance(to:wrist)
        guard scale > 0.02 else { return nil }
        if VictoryClassifier.matches(wrist:wrist,index:index,middle:middle,ring:ring,little:little) { return .victory }
        let fingers=[index,middle,ring,little]
        let thumbSpread = thumb[2].distance(to:index[0]) > scale*0.50
        // Thumb projection varies dramatically with camera angle. Its landmarks
        // must be visible, but four extended long fingers define the open palm.
        if fingers.allSatisfy(extended) { return .openPalm }
        if fingers.allSatisfy(folded) {
            // Physical 'up', not simply any extended thumb. Reject horizontal pointing.
            let t=thumb[2], base=thumb[0]
            if extended(thumb) && t.y-base.y > scale*0.65 && t.y-base.y > abs(t.x-base.x)*0.8 && thumbSpread { return .thumbsUp }
            // An uncertain or sideways thumb must not become a fist.
            if tInside(thumb[2],scale:scale) { return .fist }
        }
        return nil
    }
    private func tInside(_ tip: HandPoint, scale: Double) -> Bool { tip.distance(to:wrist) < scale*1.5 && tip.distance(to:index[0]) < scale*1.1 }
}

public struct GestureSmoother {
    private var history: [GestureKind?] = []
    public init() {}
    public mutating func update(_ raw: GestureKind?, handPresent: Bool) -> GestureKind? {
        guard handPresent else { history=[]; return nil }
        history.append(raw)
        if history.count > 5 { history.removeFirst() }
        guard history.count >= 3 else { return nil }
        for gesture in GestureKind.allCases where history.filter({ $0==gesture }).count >= 3 { return gesture }
        return nil
    }
}

public enum GestureRegion {
    /// Normalised Vision coordinates: origin is bottom left.
    public static func contains(wrist: HandPoint) -> Bool { wrist.y >= 0.20 }
}
