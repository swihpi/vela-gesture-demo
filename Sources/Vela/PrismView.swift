import SwiftUI
import AppKit
import GestureCore

struct PrismView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var camera: CameraEngine
    @ObservedObject var zoom: ZoomController
    @ObservedObject var store: MappingStore
    var onPin:(Bool)->Void
    var onClose:()->Void
    @State private var draft: GestureMapping?
    @State private var settings=false
    @AppStorage("keepAbove") private var pin=true
    @State private var restoreConfirmation=false
    var body: some View {
        VStack(spacing:0) {
            header
            Divider().opacity(0.65)
            HStack(alignment:.top,spacing:26) {
                previewColumn.frame(width:314)
                VStack(alignment:.leading,spacing:0) {
                    if settings { settingsPanel }
                    else if let item=draft { editor(item) }
                    else { mappingList }
                }.frame(maxWidth:.infinity,alignment:.topLeading)
            }.padding(24).frame(maxHeight:.infinity,alignment:.top)
            Divider().opacity(0.65)
            footer
        }
        .background(LinearGradient(colors:[Color.white.opacity(0.32),Color.blue.opacity(0.045)],startPoint:.topLeading,endPoint:.bottomTrailing))
        .background(Glass())
        .clipShape(RoundedRectangle(cornerRadius:28))
        .overlay(RoundedRectangle(cornerRadius:28).stroke(LinearGradient(colors:[.white.opacity(0.9),.white.opacity(0.15),.white.opacity(0.6)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1))
        .padding(3)
        .onAppear { onPin(pin) }
        .alert("Restore the default mappings?",isPresented:$restoreConfirmation) { Button("Cancel",role:.cancel) {}; Button("Restore",role:.destructive) { store.restoreDefaults() } } message: { Text("This replaces your current mappings with the four starting gestures.") }
    }
    var header: some View {
        HStack(spacing:12) {
            Text("✌︎").font(.system(size:30,weight:.light)).foregroundStyle(.blue).frame(width:45,height:45).background(.white.opacity(0.42),in:RoundedRectangle(cornerRadius:13))
            VStack(alignment:.leading,spacing:2) { Text("Vela").font(.system(size:23,weight:.semibold,design:.rounded)); Text("Your gestures. Your controls.").font(.system(size:11)).foregroundStyle(.secondary) }
            Spacer()
            Picker("Mode",selection:Binding(get:{ model.mode },set:{ model.setMode($0) })) {
                ForEach(StudioMode.allCases) { mode in Text(mode.title).tag(mode) }
            }.pickerStyle(.segmented).labelsHidden().frame(width:230)
            Button { settings.toggle(); draft=nil; model.editing=false; model.testMapping=nil; model.sync() } label: { Image(systemName:settings ? "arrow.left" : "gearshape").frame(width:28,height:28) }.buttonStyle(.plain).accessibilityLabel(settings ? "Back to mappings" : "Settings")
        }.padding(.horizontal,24).frame(height:82)
    }
    var previewColumn: some View {
        VStack(alignment:.leading,spacing:12) {
            ZStack {
                RoundedRectangle(cornerRadius:20).fill(Color.black.opacity(0.08))
                if camera.running {
                    Preview(session:camera.session)
                    GeometryReader { geo in
                        let w=min(geo.size.width,geo.size.height*camera.frameAspect), h=w/camera.frameAspect, x=(geo.size.width-w)/2, y=(geo.size.height-h)/2
                        RoundedRectangle(cornerRadius:10).stroke(Color.white.opacity(0.45),style:StrokeStyle(lineWidth:1,dash:[4,4])).frame(width:w-12,height:h*0.8-6).position(x:geo.size.width/2,y:y+h*0.4)
                        ForEach(Array(camera.points.enumerated()),id:\.offset) { _,p in Circle().fill(.blue).overlay(Circle().stroke(.white,lineWidth:1)).frame(width:5,height:5).position(x:x+p.x*w,y:y+p.y*h) }
                    }.allowsHitTesting(false)
                } else {
                    VStack(spacing:12) { Image(systemName:"video.slash").font(.system(size:30,weight:.light)); Text(camera.permissionPending ? "Waiting for Camera permission" : "Camera paused").font(.system(size:13)); Button("Start camera") { camera.start() }.disabled(camera.permissionPending) }
                }
                VStack { Spacer(); HStack(spacing:6) { Circle().fill(camera.running ? Color.green : .gray).frame(width:6,height:6); Text(camera.running ? "LIVE · MIRRORED" : "CAMERA PAUSED").font(.system(size:9,weight:.semibold)); Spacer(); if let gesture=camera.recognised { Text(gesture.glyph).font(.system(size:24)) } }.padding(12).background(.ultraThinMaterial) }
            }.frame(width:314,height:314).clipShape(RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(.white.opacity(0.65),lineWidth:1))
            HStack(spacing:7) { Text(camera.recognised?.glyph ?? "○").foregroundStyle(.blue); Text(camera.recognised?.title ?? "Show a gesture").fontWeight(.medium); Spacer(); Text(model.practice ? "PRACTICE" : model.enabled && !model.editing ? "LIVE ACTIONS" : "PAUSED").font(.system(size:9,weight:.semibold)).foregroundStyle(model.practice ? .orange : .secondary) }.font(.system(size:12))
            ProgressView(value:camera.progress).tint(.blue).frame(height:4)
            Text(camera.message).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2).frame(height:28,alignment:.topLeading)
        }
    }
    var mappingList: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text("Gesture mappings").font(.system(size:20,weight:.semibold)); Spacer(); Button { let unused=GestureKind.allCases.first { kind in !store.mappings.contains { $0.enabled && $0.gesture==kind } }; draft=GestureMapping(gesture:unused ?? .victory,action:.toggleVideo,enabled:unused != nil); model.editing=true; model.sync() } label: { Image(systemName:"plus").frame(width:22,height:22) }.help("Add mapping").accessibilityLabel("Add mapping") }
            Text(model.practice ? "Practice freely. Zoom will not change." : "Hold inside the outline; lower below it to reset.").font(.system(size:11)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing:0) {
                    ForEach(store.mappings) { mapping in
                        VStack(spacing:0) {
                            HStack(spacing:10) {
                                Text(mapping.gesture.glyph).font(.system(size:27)).foregroundStyle(mapping.enabled ? .blue : .gray).frame(width:34)
                                Button { draft=mapping; model.editing=true; model.sync() } label: { VStack(alignment:.leading,spacing:3) { Text(mapping.gesture.title).font(.system(size:13,weight:.semibold)); Text(mapping.action.title).font(.system(size:11)).foregroundStyle(.secondary); Text(String(format:"Hold %.1fs",mapping.hold)).font(.system(size:10)).foregroundStyle(.tertiary) }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("Edit \(mapping.gesture.title) mapping").accessibilityValue(mapping.action.title)
                                Toggle("Enable \(mapping.gesture.title)",isOn:Binding(get:{ mapping.enabled },set:{ value in var item=mapping; item.enabled=value; _=store.save(item) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                                Menu { Button("Practice gesture") { model.beginPractice(mapping) }; Button("Edit mapping") { draft=mapping; model.editing=true; model.sync() }; Button("Delete mapping",role:.destructive) { store.remove(mapping) } } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).frame(width:20).accessibilityLabel("Options for \(mapping.gesture.title)")
                            }.padding(.vertical,12)
                            Divider().opacity(0.5)
                        }
                    }
                    if store.mappings.isEmpty { Text("No mappings yet. Add one with +.").font(.system(size:12)).foregroundStyle(.secondary).padding(.vertical,30) }
                }
            }.frame(maxHeight:296)
            if let error=store.error { Text(error).font(.system(size:11)).foregroundStyle(.red) }
            if store.deleted != nil { Button("Undo deletion") { store.undoDelete() }.font(.system(size:11)) }
        }
    }
    func editor(_ item:GestureMapping) -> some View {
        let binding=Binding<GestureMapping>(get:{ draft ?? item },set:{ draft=$0 })
        return VStack(alignment:.leading,spacing:11) {
            HStack { Text("Edit mapping").font(.system(size:20,weight:.semibold)); Spacer(); Button("Cancel") { draft=nil; model.finishEditing() } }
            Text("Live actions pause while you edit. The preview stays on.").font(.system(size:11)).foregroundStyle(.secondary)
            Picker("Gesture",selection:binding.gesture) { ForEach(GestureKind.allCases) { kind in Text("\(kind.glyph)  \(kind.title)").tag(kind) } }
            Text(binding.wrappedValue.gesture.instruction).font(.system(size:11)).foregroundStyle(.secondary)
            Picker("Zoom action",selection:binding.action) { ForEach(ZoomAction.allCases) { action in Text(action.title).tag(action) } }
            HStack { Text("Hold duration"); Spacer(); Text(String(format:"%.1f seconds",binding.wrappedValue.hold)).monospacedDigit() }.font(.system(size:12))
            Slider(value:binding.hold,in:0.5...3,step:0.1).accessibilityLabel("Hold duration")
            Toggle("Mapping enabled",isOn:binding.enabled)
            if let error=store.error { Text(error).font(.system(size:11)).foregroundStyle(.red) }
            HStack { Button("Test gesture") { model.beginPractice(binding.wrappedValue) }; Spacer(); Button("Save mapping") { if store.save(binding.wrappedValue) { draft=nil; model.finishEditing() } }.buttonStyle(.borderedProminent) }
            if model.practice { Text("Practice mode is on. Switch to Live when finished.").font(.system(size:11)).foregroundStyle(.orange) }
        }.font(.system(size:12))
    }
    var settingsPanel: some View {
        VStack(alignment:.leading,spacing:15) {
            Text("Settings").font(.system(size:20,weight:.semibold))
            Label(zoom.access ? "Accessibility allowed" : "Accessibility needs setup",systemImage:zoom.access ? "checkmark.shield" : "lock").font(.system(size:12))
            HStack { Button("Camera Settings") { openSettings("Privacy_Camera") }; Button("Accessibility") { zoom.requestAccess(); openSettings("Privacy_Accessibility") } }.controlSize(.small)
            Text("Video: \(zoom.videoState.map { $0 ? "on" : "off" } ?? "unavailable") · Mic: \(zoom.microphoneState.map { $0 ? "unmuted" : "muted" } ?? "unavailable")").font(.system(size:11)).foregroundStyle(.secondary)
            Text("Computer recording: \(zoom.recordingState.map { $0 ? "active" : "stopped" } ?? "unavailable")").font(.system(size:11)).foregroundStyle(.secondary)
            Text("Raised hand: \(zoom.handState.map { $0 ? "raised" : "lowered" } ?? "unavailable")").font(.system(size:11)).foregroundStyle(.secondary)
            Toggle("Keep Vela above other windows",isOn:$pin).onChange(of:pin) { _,value in onPin(value) }
            Toggle("Allow unverified toggle shortcuts",isOn:$zoom.shortcutFallback)
            Text("Shortcut fallback applies only to video and microphone toggles. Explicit mute, unmute, video on and video off require a readable Zoom control.").font(.system(size:11)).foregroundStyle(.secondary)
            Text(model.hotkeyAvailable ? "Pause instantly: ⌃⌥⌘G" : "Pause shortcut unavailable; use Pause below").font(.system(size:12,weight:.medium))
            Text("All camera frames stay on this Mac. Vela saves no camera frames. Meeting recordings are made by Zoom.").font(.system(size:11)).foregroundStyle(.secondary)
            Button("Restore default mappings…") { restoreConfirmation=true }.controlSize(.small)
        }.font(.system(size:12))
    }
    var footer: some View {
        HStack(spacing:14) {
            VStack(alignment:.leading,spacing:4) { Text(model.lastEvent).font(.system(size:11,weight:.medium)).lineLimit(1); Text(model.practice ? "Practice mode · no Zoom commands" : zoom.lastResult=="No action yet" ? zoom.status : zoom.lastResult).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1) }.frame(maxWidth:.infinity,alignment:.leading)
            Button("Pause") { model.pause() }.controlSize(.small)
            Menu { Button("Hide panel",action:onClose); Button("Quit Vela") { NSApp.terminate(nil) } } label: { Image(systemName:"ellipsis").frame(width:20,height:25) }.menuStyle(.borderlessButton).frame(width:25)
        }.padding(.horizontal,24).frame(height:62)
    }
    private func openSettings(_ pane:String) { if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) } }
}
