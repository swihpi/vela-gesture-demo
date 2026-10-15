import SwiftUI
import Combine
import GestureCore

enum StudioMode: String, CaseIterable, Identifiable {
    case paused, practice, live
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

@MainActor final class AppModel: ObservableObject {
    let camera=CameraEngine()
    let zoom=ZoomController()
    let store=MappingStore()
    @Published var enabled=false
    @Published var practice=false
    @Published var editing=false
    @Published var testMapping: GestureMapping?
    @Published var lastEvent="Ready when you are"
    @Published var hotkeyAvailable=false
    private var subscriptions=Set<AnyCancellable>()
    init() {
        store.migrateDistinctTogglePreset()
        camera.onGesture={ [weak self] mapping in
            guard let self, self.enabled || self.practice else { return }
            if self.practice { self.lastEvent="Practice: \(mapping.gesture.title) → \(mapping.action.title)" }
            else if !self.editing && self.store.mappings.contains(mapping) { self.lastEvent="\(mapping.gesture.title) → \(mapping.action.title)"; self.zoom.perform(mapping.action) }
        }
        Publishers.CombineLatest4($enabled,$practice,$editing,$testMapping).sink { [weak self] _,_,_,_ in
            DispatchQueue.main.async { self?.sync() }
        }.store(in:&subscriptions)
        store.$mappings.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.sync() } }.store(in:&subscriptions)
    }
    var mode: StudioMode { practice ? .practice : enabled ? .live : .paused }
    func setMode(_ mode: StudioMode) {
        testMapping=nil
        switch mode {
        case .paused: pause()
        case .practice: enabled=false; practice=true; lastEvent="Practice only — Zoom will not change"
        case .live: practice=false; enabled=true; lastEvent="Live gestures enabled"
        }
        sync()
    }
    func sync() {
        var list=store.mappings
        if practice, var item=testMapping { item.enabled=true; list=[item] }
        camera.configure(mappings:list,enabled:practice || (enabled && !editing))
    }
    func beginPractice(_ mapping: GestureMapping) { practice=true; testMapping=mapping; lastEvent="Practice only — Zoom will not change"; sync() }
    func finishEditing() { editing=false; testMapping=nil; sync() }
    func pause() {
        enabled=false; practice=false; testMapping=nil
        lastEvent="Gestures paused · camera preview remains live"; sync()
    }
}
