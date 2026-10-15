import SwiftUI
import AppKit
import AVFoundation
import Carbon
import GestureCore

@main struct VelaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var current: AppDelegate?
    let model=AppModel()
    var panel: NSWindow!
    var statusItem: NSStatusItem!
    var hotkey: EventHotKeyRef?
    var handler: EventHandlerRef?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current=self
        NSApp.setActivationPolicy(.regular)
        let view=PrismView(model:model,camera:model.camera,zoom:model.zoom,store:model.store,onPin:{ [weak self] pin in self?.panel.level=pin ? .floating : .normal },onClose:{ [weak self] in self?.panel.orderOut(nil) })
        panel=NSWindow(contentRect:NSRect(x:0,y:0,width:790,height:568),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        panel.title="Vela — Gesture studio"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent=true; panel.level = .floating
        panel.delegate=self; panel.isReleasedWhenClosed=false; panel.contentMinSize=NSSize(width:790,height:568)
        panel.appearance=NSAppearance(named:.aqua); panel.backgroundColor = .clear; panel.isOpaque=false; panel.hasShadow=true
        panel.isMovableByWindowBackground=true; panel.collectionBehavior=[.fullScreenPrimary]
        panel.contentView=NSHostingView(rootView:view.environment(\.colorScheme,.light))
        panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image=NSImage(systemSymbolName:"hand.point.up.left",accessibilityDescription:"Vela gesture studio")
        statusItem.button?.target=self; statusItem.button?.action=#selector(showPanel)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(sleeping),name:NSWorkspace.willSleepNotification,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(waking),name:NSWorkspace.didWakeNotification,object:nil)
        var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),{ _,_,_ in
            DispatchQueue.main.async { AppDelegate.current?.model.pause() }; return noErr
        },1,&spec,nil,&handler)
        let id=EventHotKeyID(signature:0x56454C41,id:1)
        model.hotkeyAvailable=RegisterEventHotKey(UInt32(kVK_ANSI_G),UInt32(controlKey | optionKey | cmdKey),id,GetApplicationEventTarget(),0,&hotkey)==noErr
        model.zoom.refresh()
        #if DEBUG
        if !ProcessInfo.processInfo.arguments.contains("--documentation-snapshot") { model.camera.start() }
        #else
        model.camera.start()
        #endif
        #if DEBUG
        // Explicit local integration check; absent from the public release build.
        if ProcessInfo.processInfo.arguments.contains("--check-zoom-hand") {
            DispatchQueue.main.asyncAfter(deadline:.now()+1) { [weak self] in
                self?.model.zoom.perform(.toggleHand)
            }
        }
        #endif
    }
    @objc func sleeping() { model.pause(); model.camera.stop() }
    @objc func waking() { model.camera.start() }
    @objc func showPanel() {
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func windowShouldClose(_ sender:NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool) -> Bool { showPanel(); return false }
    func applicationWillTerminate(_ notification:Notification) {
        model.camera.stop()
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
