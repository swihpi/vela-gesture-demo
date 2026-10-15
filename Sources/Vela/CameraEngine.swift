import AVFoundation
import Vision
import AppKit
import GestureCore

final class CameraEngine: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var running = false
    @Published var permissionPending = false
    @Published var message = "Enable gesture control to begin"
    @Published var progress = 0.0
    @Published var armed = true
    @Published var cameraName = "MacBook Air camera"
    @Published var points: [CGPoint] = []
    @Published var handVisible = false
    @Published var frameAspect: CGFloat = 4.0/3.0
    @Published var recognised: GestureKind?
    @Published var gesturesEnabled = false
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.vela.capture", qos: .userInitiated)
    private var gate = MappingGate(requireNeutral:true)
    private var smoother=GestureSmoother()
    private var activeMappings: [GestureMapping] = []
    private var revision = 0
    private var lastFrame = 0.0
    private var configured = false
    private var desired = false
    var onGesture: ((GestureMapping) -> Void)?
    func configure(mappings: [GestureMapping], enabled: Bool) {
        gesturesEnabled=enabled
        revision += 1
        let currentRevision=revision
        queue.async {
            self.activeMappings=enabled ? mappings.filter(\.enabled) : []
            self.gate=MappingGate(requireNeutral:true); self.smoother=GestureSmoother()
            self.captureRevision=currentRevision
        }
    }
    private var captureRevision = 0
    private var lastDiagnostic=0.0
    private func diagnostic(_ message: String,at time: Double) {
        guard time-lastDiagnostic > 0.6, let index=CommandLine.arguments.firstIndex(of:"--diagnostics-path"), CommandLine.arguments.indices.contains(index+1) else { return }
        lastDiagnostic=time
        try? Data(message.utf8).write(to:URL(fileURLWithPath:CommandLine.arguments[index+1]),options:.atomic)
    }
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(captureFailed), name: .AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(captureInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
    }
    @objc private func captureFailed() { stop(); DispatchQueue.main.async { self.message = "Camera stopped. Disable and enable to retry." } }
    @objc private func captureInterrupted() { stop(); DispatchQueue.main.async { self.message = "Camera interrupted. Enable to retry." } }
    func start() {
        desired = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart()
        case .notDetermined:
            permissionPending = true; message = "Waiting for macOS Camera permission…"
            NSApp.activate(ignoringOtherApps:true)
            AVCaptureDevice.requestAccess(for:.video) { allowed in DispatchQueue.main.async { self.permissionPending = false; if allowed && self.desired { self.configureAndStart() } else { self.message = "Allow Camera access in System Settings" } } }
        default: message = "Allow Camera access in System Settings"
        }
    }
    func stop() {
        desired = false
        permissionPending = false
        running = false; progress = 0; points = []; handVisible = false
        queue.async {
            self.session.stopRunning(); self.gate=MappingGate(requireNeutral:true)
            DispatchQueue.main.async { self.running = false; self.progress = 0; self.points = []; self.handVisible = false; self.message = "Gesture control paused" }
        }
    }
    private func configureAndStart() {
        queue.async {
            do {
                if !self.configured {
                    let cameras = AVCaptureDevice.DiscoverySession(deviceTypes:[.builtInWideAngleCamera], mediaType:.video, position:.unspecified).devices
                    guard let device = cameras.first(where: { $0.deviceType == .builtInWideAngleCamera && !$0.localizedName.lowercased().contains("logitech") }) else { throw CameraError.noBuiltIn }
                    let input = try AVCaptureDeviceInput(device:device)
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .vga640x480
                    guard self.session.canAddInput(input) else { self.session.commitConfiguration(); throw CameraError.unavailable }
                    self.session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self,queue:self.queue)
                    guard self.session.canAddOutput(output) else { self.session.removeInput(input); self.session.commitConfiguration(); throw CameraError.unavailable }
                    self.session.addOutput(output); self.session.commitConfiguration(); self.configured = true
                    DispatchQueue.main.async { self.cameraName = device.localizedName }
                }
                self.gate=MappingGate(requireNeutral:true); self.session.startRunning()
                let active = self.session.isRunning
                DispatchQueue.main.async {
                    if !self.desired { self.stop(); return }
                    self.running = active; self.message = active ? "Show a gesture to the camera" : "Could not start the built-in camera"
                }
            } catch { DispatchQueue.main.async { self.running = false; self.message = error.localizedDescription } }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now-lastFrame >= 0.09, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        let frameAspect=CGFloat(CVPixelBufferGetWidth(pixelBuffer))/CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let request = VNDetectHumanHandPoseRequest(); request.maximumHandCount = 2
        do {
            try VNImageRequestHandler(cvPixelBuffer:pixelBuffer,orientation:.up).perform([request])
            var gesture: GestureKind?; var dots: [CGPoint] = []
            var reliable = true
            var inZone = false
            let raisedHand=request.results?.max { a,b in
                ((try? a.recognizedPoint(.wrist).location.y) ?? 0) < ((try? b.recognizedPoint(.wrist).location.y) ?? 0)
            }
            if let hand = raisedHand {
                let p = try hand.recognizedPoints(.all)
                if let wrist=p[.wrist],wrist.confidence >= 0.25 { inZone=GestureRegion.contains(wrist:HandPoint(wrist.location.x,wrist.location.y)) }
                let required: [VNHumanHandPoseObservation.JointName] = [.wrist,.indexMCP,.indexPIP,.indexTip,.middleMCP,.middlePIP,.middleTip,.ringMCP,.ringPIP,.ringTip,.littleMCP,.littlePIP,.littleTip]
                reliable=required.allSatisfy({ (p[$0]?.confidence ?? 0) >= 0.35 })
                if reliable {
                    func point(_ name: VNHumanHandPoseObservation.JointName) -> HandPoint { HandPoint(Double(p[name]!.location.x),Double(p[name]!.location.y)) }
                    let index=[point(.indexMCP),point(.indexPIP),point(.indexTip)], middle=[point(.middleMCP),point(.middlePIP),point(.middleTip)], ring=[point(.ringMCP),point(.ringPIP),point(.ringTip)], little=[point(.littleMCP),point(.littlePIP),point(.littleTip)]
                    if VictoryClassifier.matches(wrist:point(.wrist),index:index,middle:middle,ring:ring,little:little) { gesture = .victory }
                    else if [VNHumanHandPoseObservation.JointName.thumbMP,.thumbIP,.thumbTip].allSatisfy({ (p[$0]?.confidence ?? 0) >= 0.35 }) {
                        let pose=HandPose(wrist:point(.wrist),thumb:[point(.thumbMP),point(.thumbIP),point(.thumbTip)],index:index,middle:middle,ring:ring,little:little)
                        gesture=pose.classify()
                        diagnostic("\(gesture?.title ?? "Unrecognised"): \(pose.diagnosticDescription)",at:now)
                    } else { reliable=false }
                }
                dots = p.values.filter { $0.confidence > 0.35 }.map { CGPoint(x:1-$0.location.x,y:1-$0.location.y) }
            }
            if !inZone { gesture=nil; dots=[] }
            gesture=smoother.update(gesture,handPresent:inZone && !dots.isEmpty)
            let mapping=activeMappings.first { $0.gesture==gesture }
            var fired: GestureMapping?
            if gesture != nil || dots.isEmpty || (reliable && gesture == nil && self.gate.armed == false) {
                // An unmapped recognised gesture is not a neutral release.
                if gate.update(gesture,at:now,hold:mapping?.hold ?? 1) != nil { fired=mapping }
            } else { gate.uncertain(at:now) }
            let progress = mapping == nil ? 0 : gate.progress, armed = gate.armed
            let frameRevision=captureRevision
            DispatchQueue.main.async {
                guard self.running, self.revision==frameRevision else { return }
                self.frameAspect=frameAspect; self.progress = progress; self.armed = armed; self.points = dots; self.handVisible = !dots.isEmpty; self.recognised=gesture
                self.message = !self.gesturesEnabled ? "Gestures paused · preview stays live" : !reliable ? "Keep all fingers in view" : !armed ? "Lower your hand below the outlined area" : mapping != nil ? "Hold \(mapping!.gesture.title.lowercased()) for \(String(format:"%.1f",mapping!.hold))s" : gesture != nil ? "No enabled mapping for this gesture" : "Show a gesture to the camera"
                if let fired, self.gesturesEnabled { self.onGesture?(fired) }
            }
        } catch {
            // Tracking errors must break a hold without re-arming a latched gesture.
            gate.interrupt()
            DispatchQueue.main.async { self.message = "Tracking unavailable. Keep your hand in view."; self.progress = 0 }
        }
    }
    enum CameraError: LocalizedError {
        case noBuiltIn, unavailable
        var errorDescription: String? { self == .noBuiltIn ? "Built-in camera not found. Open the MacBook lid." : "Built-in camera is unavailable. Close other camera apps and retry." }
    }
}
