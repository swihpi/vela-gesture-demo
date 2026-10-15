import AppKit
import ApplicationServices
import GestureCore

@MainActor final class ZoomController: ObservableObject {
    @Published var status = "Zoom status not checked"
    @Published var lastResult = "No action yet"
    @Published var access = AXIsProcessTrusted()
    @Published var videoState: Bool?
    @Published var microphoneState: Bool?
    @Published var recordingState: Bool?
    @Published var handState: Bool?
    @Published var busy = false
    @Published var shortcutFallback = UserDefaults.standard.bool(forKey:"shortcutFallback") { didSet { UserDefaults.standard.set(shortcutFallback,forKey:"shortcutFallback") } }
    private var timer: Timer?
    private var didRequestAccess = false
    init() { timer=Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in Task { @MainActor in self?.refresh() } } }
    func requestAccess() {
        access=AXIsProcessTrusted()
        guard !access else { refresh(); return }
        guard !didRequestAccess else { status="Enable Vela in Accessibility, then return here"; return }
        didRequestAccess=true
        access=AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)
    }
    private var zoom: NSRunningApplication? { NSRunningApplication.runningApplications(withBundleIdentifier:"us.zoom.xos").first }
    private func value(_ e: AXUIElement,_ key: String) -> CFTypeRef? { var v: CFTypeRef?; guard AXUIElementCopyAttributeValue(e,key as CFString,&v) == .success else { return nil }; return v }
    private struct Controls {
        var video: (AXUIElement,Bool)?
        var mic: (AXUIElement,Bool)?
        var recording: (AXUIElement,Bool)?
        var hand: (AXUIElement,Bool)?
        var meetingAvailable=false
        var localRecordShortcut: AXUIElement?
    }
    private func controls() -> Controls {
        guard let zoom else { return Controls() }
        let app=AXUIElementCreateApplication(zoom.processIdentifier)
        AXUIElementSetMessagingTimeout(app,0.20)
        var result=Controls(), budget=700
        // Zoom exposes its own audio/video menu commands with stable identifiers.
        // This avoids confusing a participant's Mute button with our microphone.
        func menuSearch(_ e: AXUIElement,_ depth:Int) {
            guard depth < 8 else { return }
            let id=value(e,kAXIdentifierAttribute) as? String ?? ""
            let title=(value(e,kAXTitleAttribute) as? String ?? "").lowercased()
            if id=="onLocalRecord:" {
                result.localRecordShortcut=e
                if title.contains("stop") { result.recording=(e,true) }
                else if title.contains("record") && !title.contains("pause") && !title.contains("resume") { result.recording=(e,false) }
            }
            if (id.lowercased().contains("stop") && id.lowercased().contains("record") && !id.lowercased().contains("cloud")) || title=="stop recording" || title=="stop computer recording" {
                result.recording=(e,true)
            }
            // Exact own-hand menu titles avoid participant-list moderation controls.
            if let raised=ZoomHandControl.state(menuTitle:title) { result.hand=(e,raised) }
            if id=="onMuteAudio:" {
                if title.hasPrefix("unmute") { result.mic=(e,false) }
                else if title.hasPrefix("mute") { result.mic=(e,true) }
            }
            if id=="onMuteVideo:" {
                if title.hasPrefix("stop") { result.video=(e,true) }
                else if title.hasPrefix("start") { result.video=(e,false) }
            }
            for child in (value(e,kAXChildrenAttribute) as? [AXUIElement] ?? []) { menuSearch(child,depth+1) }
        }
        if let menu=value(app,kAXMenuBarAttribute) { menuSearch(menu as! AXUIElement,0) }
        var foundVideoButton=false
        func search(_ e: AXUIElement,_ depth:Int) {
            budget -= 1
            guard budget > 0, depth < 14, !foundVideoButton else { return }
            if (value(e,kAXRoleAttribute) as? String) == kAXButtonRole {
                let labels=[kAXTitleAttribute,kAXDescriptionAttribute,kAXHelpAttribute].compactMap { value(e,$0) as? String }
                for label in labels {
                    let s=label.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
                    if s.hasPrefix("stop video") || s.hasPrefix("stop my video") { result.video=(e,true); foundVideoButton=true }
                    else if s.hasPrefix("start video") || s.hasPrefix("start my video") { result.video=(e,false); foundVideoButton=true }

                }
            }
            for child in (value(e,kAXChildrenAttribute) as? [AXUIElement] ?? []) { search(child,depth+1) }
        }
        // Search meeting windows first. Never operate participant-list mute controls.
        let windows=value(app,kAXWindowsAttribute) as? [AXUIElement] ?? []
        for window in windows {
            let title=(value(window,kAXTitleAttribute) as? String ?? "").lowercased()
            if (value(window,kAXIdentifierAttribute) as? String) == "zm.meeting.window.main" || title.contains("meeting") || title.contains("webinar") { result.meetingAvailable=true; search(window,0) }
        }
        return result
    }
    func refresh() {
        access=AXIsProcessTrusted(); guard !busy else { return }
        guard zoom != nil else { videoState=nil; microphoneState=nil; recordingState=nil; handState=nil; status="Zoom is not running"; return }
        guard access else { videoState=nil; microphoneState=nil; recordingState=nil; handState=nil; status="Allow Accessibility to control Zoom"; return }
        let found=controls(); videoState=found.video?.1; microphoneState=found.mic?.1; recordingState=found.recording?.1; handState=found.hand?.1
        status = videoState != nil || microphoneState != nil || handState != nil ? "Connected to Zoom" : "Open a Zoom meeting to connect"
    }
    func toggle() { perform(.toggleVideo) }
    func perform(_ action: ZoomAction) {
        guard !busy else { lastResult="Wait for the previous Zoom command"; return }
        access=AXIsProcessTrusted()
        guard let zoom else { lastResult="Zoom is not running"; return }
        guard access else { lastResult="Accessibility needs setup — open Vela’s Settings"; return }
        let found=controls(), control=action.isHand ? found.hand : action.isRecording ? found.recording : action.isVideo ? found.video : found.mic
        if let (button,wasOn)=control {
            let target=action.target(from:wasOn)
            if target==wasOn { lastResult=stateText(action:action,on:wasOn)+" already"; return }
            if let enabled=value(button,kAXEnabledAttribute) as? Bool, !enabled { lastResult="Zoom has disabled this control"; return }
            let role=value(button,kAXRoleAttribute) as? String
            if role==kAXMenuItemRole {
                // Hidden menu-item AXPress may only select the item. Use Zoom's
                // actual menu accelerator, then verify its state changed.
                guard sendMenuShortcut(action.isRecording ? (found.localRecordShortcut ?? button) : button,to:zoom) else { lastResult="Zoom shortcut unavailable; open the meeting controls"; return }
            } else {
                guard AXUIElementPerformAction(button,kAXPressAction as CFString) == .success else { lastResult="Zoom did not accept the command"; return }
            }
            busy=true; lastResult="Checking Zoom…"
            DispatchQueue.main.asyncAfter(deadline:.now()+0.9) { [weak self] in
                guard let self else { return }; self.busy=false
                let current=self.controls(), on=(action.isHand ? current.hand : action.isRecording ? current.recording : action.isVideo ? current.video : current.mic)?.1
                if let on { self.lastResult = on==target ? self.stateText(action:action,on:on) : action.isRecording ? "Check Zoom’s recording prompt or host permission" : "Zoom state did not change — check host restrictions" }
                else { self.lastResult="Command sent; Zoom state unavailable" }
                self.refresh()
            }
        } else if action.isHand && found.meetingAvailable {
            // Some Zoom versions expose no own-hand menu item. Zoom documents
            // Option-Y as the raise/lower toggle; never route it through mic fallback.
            guard postShortcut(key:16,flags:[.maskAlternate],to:zoom) else { lastResult="Could not send Zoom hand shortcut"; return }
            busy=true; lastResult="Raise/lower hand shortcut sent; check Zoom"
            DispatchQueue.main.asyncAfter(deadline:.now()+0.9) { [weak self] in
                self?.busy=false; self?.refresh()
            }
        } else if shortcutFallback && [.toggleVideo,.toggleMicrophone].contains(action) {
            let source=CGEventSource(stateID:.combinedSessionState), key:CGKeyCode=action.isVideo ? 9 : 0
            let down=CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:true), up=CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:false)
            down?.flags=[.maskCommand,.maskShift]; up?.flags=[.maskCommand,.maskShift]
            down?.postToPid(zoom.processIdentifier); up?.postToPid(zoom.processIdentifier)
            lastResult="Toggle shortcut sent; state unverified"
        } else { lastResult=action.isHand ? "Raise/lower hand unavailable — open a Zoom meeting" : action.isRecording ? "Computer recording unavailable — check Zoom host permission" : "Zoom control unavailable; no action sent" }
    }
    private func stateText(action:ZoomAction,on:Bool) -> String {
        if action.isHand { return on ? "Zoom hand raised" : "Zoom hand lowered" }
        if action.isRecording { return on ? "Zoom recording started" : "Zoom recording stopped" }
        return action.isVideo ? (on ? "Video on" : "Video off") : (on ? "Microphone unmuted" : "Microphone muted")
    }
    private func sendMenuShortcut(_ item:AXUIElement,to zoom:NSRunningApplication) -> Bool {
        let character=(value(item,kAXMenuItemCmdCharAttribute) as? String ?? "").lowercased()
        let keys: [String:CGKeyCode] = ["a":0,"v":9,"r":15,"y":16]
        guard let key=keys[character], let modifiers=value(item,kAXMenuItemCmdModifiersAttribute) as? Int else { return false }
        var flags=CGEventFlags()
        if modifiers & 8 == 0 { flags.insert(.maskCommand) }
        if modifiers & 1 != 0 { flags.insert(.maskShift) }
        if modifiers & 2 != 0 { flags.insert(.maskAlternate) }
        if modifiers & 4 != 0 { flags.insert(.maskControl) }
        return postShortcut(key:key,flags:flags,to:zoom)
    }
    private func postShortcut(key:CGKeyCode,flags:CGEventFlags,to zoom:NSRunningApplication) -> Bool {
        let source=CGEventSource(stateID:.combinedSessionState)
        guard let down=CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:true), let up=CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:false) else { return false }
        down.flags=flags; up.flags=flags
        down.postToPid(zoom.processIdentifier); up.postToPid(zoom.processIdentifier)
        return true
    }
}
