import Foundation
import Combine

@MainActor public final class MappingStore: ObservableObject {
    @Published public private(set) var mappings: [GestureMapping] = []
    @Published public var error: String?
    @Published public private(set) var deleted: GestureMapping?
    private var deletedIndex = 0
    private let defaults: UserDefaults
    private let key = "gestureMappings.v1"
    public init(defaults: UserDefaults = .standard) {
        self.defaults=defaults
        if let data=defaults.data(forKey:key) {
            do {
                let saved=try JSONDecoder().decode([GestureMapping].self,from:data)
                if let issue=GestureMapping.validationError(saved) { throw StoreError.invalid(issue) }
                mappings=saved
            } catch {
                // Preserve invalid data for recovery; never silently replace it with active actions.
                self.error="Saved mappings could not be read. Restore defaults to recover."
                mappings=[]
            }
        } else { mappings=GestureMapping.defaults; persist() }
    }
    public func save(_ mapping: GestureMapping) -> Bool {
        var copy=mappings
        if let index=copy.firstIndex(where: { $0.id==mapping.id }) { copy[index]=mapping } else { copy.append(mapping) }
        guard let issue=GestureMapping.validationError(copy) else { mappings=copy; error=nil; persist(); return true }
        error=issue; return false
    }
    public func remove(_ mapping: GestureMapping) {
        guard let index=mappings.firstIndex(where: { $0.id==mapping.id }) else { return }
        deleted=mapping; deletedIndex=index; mappings.remove(at:index); error=nil; persist()
    }
    public func undoDelete() {
        guard var item=deleted else { return }
        if mappings.contains(where: { $0.enabled && $0.gesture==item.gesture }) { item.enabled=false }
        mappings.insert(item,at:min(deletedIndex,mappings.count)); deleted=nil; persist()
    }
    /// Explicit user-requested preset migration; keep existing row IDs and hold durations.
    public func applyTogglePreset() {
        var revised=mappings
        for preset in GestureMapping.defaults {
            if let index=revised.firstIndex(where: { $0.gesture==preset.gesture && $0.enabled }) ?? revised.firstIndex(where: { $0.gesture==preset.gesture }) {
                revised[index].action=preset.action; revised[index].enabled=true
                for other in revised.indices where other != index && revised[other].gesture==preset.gesture { revised[other].enabled=false }
            } else { revised.append(preset) }
        }
        mappings=revised; error=nil; persist()
    }
    /// Upgrade only the old default actions; preserve edits, disabled rows, IDs and holds.
    public func migrateDistinctTogglePreset() {
        guard !defaults.bool(forKey:"distinctTogglePreset.v3"), error == nil else { return }
        for index in mappings.indices {
            if mappings[index].gesture == .openPalm && mappings[index].action == .toggleVideo {
                mappings[index].action = .toggleMicrophone
            } else if mappings[index].gesture == .thumbsUp && mappings[index].action == .toggleMicrophone {
                mappings[index].action = .toggleHand
            }
        }
        persist()
        defaults.set(true,forKey:"distinctTogglePreset.v3")
    }
    public func restoreDefaults() { mappings=GestureMapping.defaults; deleted=nil; error=nil; persist() }
    private func persist() {
        do { defaults.set(try JSONEncoder().encode(mappings),forKey:key) }
        catch { self.error="Mappings could not be saved." }
    }
    enum StoreError: Error { case invalid(String) }
}
