import SwiftUI
import AppKit
import AVFoundation

struct Preview: NSViewRepresentable {
    let session: AVCaptureSession
    final class Surface: NSView {
        let preview=AVCaptureVideoPreviewLayer()
        override init(frame:NSRect) { super.init(frame:frame); wantsLayer=true; layer?.addSublayer(preview); preview.videoGravity = .resizeAspect }
        required init?(coder:NSCoder) { fatalError() }
        override func layout() {
            super.layout(); preview.frame=bounds
            if let c=preview.connection,c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring=false; c.isVideoMirrored=true }
        }
    }
    func makeNSView(context:Context) -> Surface { let view=Surface(); view.preview.session=session; return view }
    func updateNSView(_ view:Surface,context:Context) { view.needsLayout=true }
}
struct Glass: NSViewRepresentable {
    func makeNSView(context:Context) -> NSVisualEffectView { let v=NSVisualEffectView(); v.appearance=NSAppearance(named:.aqua); v.material = .popover; v.blendingMode = .behindWindow; v.state = .active; return v }
    func updateNSView(_ view:NSVisualEffectView,context:Context) {}
}
