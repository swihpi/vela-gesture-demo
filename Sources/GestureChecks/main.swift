import Foundation
import GestureCore
var count = 0
@MainActor func check(_ value: Bool, _ message: String) { precondition(value, message); count += 1 }
var g = GestureGate(); var triggers = 0
for i in 0...60 { if g.update(isVictory:true, at:Double(i)/10) { triggers += 1 } }
check(triggers == 1, "A held V must trigger once")
check(!g.armed, "Must remain latched")
for i in 61...63 { _ = g.update(isVictory:false,at:Double(i)/10) }
check(!g.armed, "Brief detection loss must not re-arm")
_ = g.update(isVictory:true, at:6.4)
for i in 65...74 { _ = g.update(isVictory:false,at:Double(i)/10) }
check(g.armed, "Deliberate release re-arms")
for i in 75...90 { if g.update(isVictory:true,at:Double(i)/10) { triggers += 1 } }
check(triggers == 2, "Second gesture must trigger once")
g.reset(); _ = g.update(isVictory:true,at:0); _ = g.update(isVictory:true,at:0.1)
check(!g.update(isVictory:true,at:5), "Capture stall must not trigger")
g.reset(); _ = g.update(isVictory:true,at:0); _ = g.update(isVictory:false,at:0.4)
check(!g.update(isVictory:true,at:0.5), "Interrupted hold must restart")
let w = HandPoint(0,0)
let i = [HandPoint(0.1,0.3),HandPoint(0.15,0.5),HandPoint(0.2,0.8)]
let m = [HandPoint(-0.1,0.3),HandPoint(-0.15,0.5),HandPoint(-0.2,0.85)]
let f = [HandPoint(0.2,0.25),HandPoint(0.25,0.4),HandPoint(0.2,0.2)]
check(VictoryClassifier.matches(wrist:w,index:i,middle:m,ring:f,little:f), "Recognise V")
check(!VictoryClassifier.matches(wrist:w,index:i,middle:m,ring:i,little:i), "Reject open palm")
check(!VictoryClassifier.matches(wrist:w,index:f,middle:f,ring:f,little:f), "Reject fist")
var latched = GestureGate()
for n in 0...12 { _ = latched.update(isVictory:true,at:Double(n)/10) }
latched.interrupt()
check(!latched.armed, "A tracking error must not re-arm")
check(!latched.update(isVictory:true,at:4), "Same gesture after tracking error must not trigger")
print("GestureChecks: \(count) checks passed")

var mg=MappingGate()
var mapped: [GestureKind]=[]
for n in 0...12 { if let result=mg.update(.victory,at:Double(n)/10,hold:1) { mapped.append(result) } }
for n in 13...30 { if let result=mg.update(.openPalm,at:Double(n)/10,hold:1) { mapped.append(result) } }
check(mapped == [.victory],"Switching directly between poses must not fire a second action")
for n in 31...39 { _=mg.update(nil,at:Double(n)/10,hold:1) }
for n in 40...55 { if let result=mg.update(.openPalm,at:Double(n)/10,hold:1) { mapped.append(result) } }
check(mapped == [.victory,.openPalm],"Neutral release allows the next pose")
var change=MappingGate()
for n in 0...7 { _=change.update(.victory,at:Double(n)/10,hold:1) }
check(change.update(.fist,at:0.8,hold:1)==nil,"Changing pose restarts the hold")
check(change.progress==0,"New pose cannot inherit hold progress")
var initial=MappingGate(requireNeutral:true)
for n in 0...20 { _=initial.update(.victory,at:Double(n)/10,hold:1) }
check(!initial.armed,"Enabling mid-gesture must wait for neutral")
initial.interrupt()
check(!initial.armed,"Tracking errors must preserve the shared latch")
check(ZoomAction.mute.target(from:false)==false,"Mute must never unmute")
check(ZoomAction.videoOff.target(from:false)==false,"Video off must never turn video on")
check(ZoomAction.unmute.target(from:true)==true,"Unmute must not toggle a live microphone off")
let flatThumb=[HandPoint(-0.15,0.15),HandPoint(-0.35,0.30),HandPoint(-0.6,0.5)]
let tuckedThumb=[HandPoint(-0.05,0.15),HandPoint(0.05,0.25),HandPoint(0.1,0.2)]
let upThumb=[HandPoint(-0.2,0.15),HandPoint(-0.2,0.4),HandPoint(-0.2,0.7)]
check(HandPose(wrist:w,thumb:tuckedThumb,index:i,middle:m,ring:f,little:f).classify( ) == .victory,"V classification")
check(HandPose(wrist:w,thumb:flatThumb,index:i,middle:m,ring:i,little:m).classify( ) == .openPalm,"Open palm classification")
check(HandPose(wrist:w,thumb:tuckedThumb,index:f,middle:f,ring:f,little:f).classify( ) == .fist,"Fist classification")
check(HandPose(wrist:w,thumb:upThumb,index:f,middle:f,ring:f,little:f).classify( ) == .thumbsUp,"Thumbs-up classification")
check(HandPose(wrist:w,thumb:[],index:f,middle:f,ring:f,little:f).classify()==nil,"Reject incomplete hand")
let suite="com.swi.vela.checks.\(UUID().uuidString)"
let prefs=UserDefaults(suiteName:suite)!
prefs.removePersistentDomain(forName:suite)
let store=MappingStore(defaults:prefs)
check(store.mappings.count==4,"Fresh install has four mappings")
check(store.mappings.first(where:{$0.gesture == .victory})?.action == .toggleVideo,"Preserve original V mapping")
var edited=store.mappings[0];edited.action = .mute;edited.hold=1.7
check(store.save(edited),"Save edited mapping")
check(MappingStore(defaults:prefs).mappings[0]==edited,"Mapping edits survive store reload")
var duplicate=edited;duplicate.id=UUID()
check(!store.save(duplicate),"Reject duplicate active gestures")
check(store.mappings.count==4,"Rejected duplicate must not change saved mappings")
duplicate.enabled=false
check(store.save(duplicate),"Allow disabled duplicate")
store.remove(edited)
check(!MappingStore(defaults:prefs).mappings.contains(where:{$0.id==edited.id}),"Deletion persists")
store.undoDelete()
check(store.mappings.contains(edited),"Undo restores deleted mapping")
store.mappings.forEach { store.remove($0) }
check(MappingStore(defaults:prefs).mappings.isEmpty,"An intentionally empty mapping list must survive restart")
var invalid=edited;invalid.hold=0
check(!store.save(invalid),"Reject invalid hold duration")
prefs.set(Data("not json".utf8),forKey:"gestureMappings.v1")
let damaged=MappingStore(defaults:prefs)
check(damaged.mappings.isEmpty && damaged.error != nil,"Corrupt preferences must not silently enable default actions")
prefs.removePersistentDomain(forName:suite)
print("Expanded GestureChecks: \(count) checks passed")

let curvedThumb=[HandPoint(-0.15,0.15),HandPoint(-0.4,0.28),HandPoint(-0.4,0.45)]
check(HandPose(wrist:w,thumb:curvedThumb,index:i,middle:m,ring:i,little:m).classify() == .openPalm,"A naturally bent but spread thumb must count as an open palm")
check(HandPose(wrist:w,thumb:tuckedThumb,index:i,middle:m,ring:i,little:m).classify() == .openPalm,"A relaxed thumb must not prevent an otherwise open palm")
check(HandPose(wrist:w,thumb:flatThumb,index:f,middle:m,ring:i,little:m).classify() != .openPalm,"A bent index finger is not an open palm")
print("Final GestureChecks: \(count) checks passed")
var smooth=GestureSmoother()
_=smooth.update(.openPalm,handPresent:true);_=smooth.update(.openPalm,handPresent:true)
check(smooth.update(.openPalm,handPresent:true) == .openPalm,"Stable palm passes voting")
check(smooth.update(nil,handPresent:true) == .openPalm,"One tracking dropout preserves palm")
check(smooth.update(nil,handPresent:false) == nil,"Hand leaving frame clears pose immediately")
var tolerance=MappingGate()
for n in 0...5 { _=tolerance.update(.openPalm,at:Double(n)/10,hold:1) }
tolerance.uncertain(at:0.6);tolerance.uncertain(at:0.7)
check(tolerance.update(.openPalm,at:0.8,hold:1)==nil,"A tracking gap cannot complete a hold")
var palmTriggered=false
for n in 9...14 { if tolerance.update(.openPalm,at:Double(n)/10,hold:1) == .openPalm { palmTriggered=true } }
check(palmTriggered,"Short tracking gaps can still complete a deliberate palm hold")
tolerance.uncertain(at:1.5);tolerance.uncertain(at:2)
check(!tolerance.armed,"Tracking uncertainty never re-arms a latched gesture")
print("Tracking GestureChecks: \(count) checks passed")

check(!GestureRegion.contains(wrist:HandPoint(0.5,0.1)),"Resting hands below the outline must not keep the latch active")
check(GestureRegion.contains(wrist:HandPoint(0.5,0.4)),"Raised hand falls inside the active area")
print("Release GestureChecks: \(count) checks passed")

check(GestureMapping.defaults.first(where:{$0.gesture == .openPalm})?.action == .toggleMicrophone,"Palm toggles microphone")
check(GestureMapping.defaults.first(where:{$0.gesture == .fist})?.action == .toggleRecording,"New fist default toggles recording")
check(GestureMapping.defaults.first(where:{$0.gesture == .thumbsUp})?.action == .toggleHand,"Thumbs up raises or lowers hand")
check(ZoomAction.toggleRecording.target(from:false),"Recording toggle starts from stopped")
check(!ZoomAction.toggleRecording.target(from:true),"Recording toggle stops from active")
let migrationSuite="com.swi.vela.migration.\(UUID().uuidString)"
let migrationPrefs=UserDefaults(suiteName:migrationSuite)!
let migrationStore=MappingStore(defaults:migrationPrefs)
let originalIDs=migrationStore.mappings.map(\.id)
var oldPalm=migrationStore.mappings.first(where:{$0.gesture == .openPalm})!;oldPalm.action = .mute
_=migrationStore.save(oldPalm)
migrationStore.applyTogglePreset()
check(migrationStore.mappings.map(\.id)==originalIDs,"Preset migration preserves mapping identifiers")
check(migrationStore.mappings.first(where:{$0.gesture == .openPalm})?.action == .toggleMicrophone,"Preset migration updates the existing palm mapping")
check(MappingStore(defaults:migrationPrefs).mappings==migrationStore.mappings,"Migrated preset persists")
migrationPrefs.removePersistentDomain(forName:migrationSuite)
print("Toggle GestureChecks: \(count) checks passed")

check(Set(GestureMapping.defaults.map(\.action)).count == 4,"Each default gesture has a distinct action")
check(ZoomAction.toggleHand.target(from:false),"Hand toggle raises a lowered hand")
check(!ZoomAction.toggleHand.target(from:true),"Hand toggle lowers a raised hand")
check(ZoomHandControl.state(menuTitle:"Raise Hand") == false,"Raise menu means hand is lowered")
check(ZoomHandControl.state(menuTitle:" Lower My Hand ") == true,"Lower menu means hand is raised")
check(ZoomHandControl.state(menuTitle:"Lower All Hands") == nil,"Never use participant moderation controls")
check(ZoomHandControl.state(menuTitle:"Reactions") == nil,"Never infer hand state from reactions")
let upgradeSuite="com.swi.vela.upgrade.\(UUID().uuidString)"
let upgradePrefs=UserDefaults(suiteName:upgradeSuite)!
let upgrade=MappingStore(defaults:upgradePrefs)
var palm=upgrade.mappings.first { $0.gesture == .openPalm }!; palm.action = .toggleVideo; palm.hold=2.1; palm.enabled=false
var thumb=upgrade.mappings.first { $0.gesture == .thumbsUp }!; thumb.action = .toggleMicrophone
_=upgrade.save(palm); _=upgrade.save(thumb)
let upgradeIDs=upgrade.mappings.map(\.id)
upgrade.migrateDistinctTogglePreset()
check(upgrade.mappings.map(\.id)==upgradeIDs,"Upgrade preserves IDs")
let upgradedPalm=upgrade.mappings.first { $0.gesture == .openPalm }!
check(upgradedPalm.action == .toggleMicrophone && upgradedPalm.hold == 2.1 && !upgradedPalm.enabled,"Upgrade corrects old defaults without enabling disabled rows or changing holds")
check(upgrade.mappings.first { $0.gesture == .thumbsUp }?.action == .toggleHand,"Upgrade corrects old thumbs-up default")
var custom=upgrade.mappings.first { $0.gesture == .thumbsUp }!; custom.action = .videoOff
_=upgrade.save(custom); upgrade.migrateDistinctTogglePreset()
check(upgrade.mappings.contains(custom),"Migration runs once and preserves later edits")
check(MappingStore(defaults:upgradePrefs).mappings==upgrade.mappings,"Upgrade persists across restarts")
print("Distinct-action GestureChecks: \(count) checks passed")

upgradePrefs.removeObject(forKey:"distinctTogglePreset.v3")
let beforeCustomUpgrade=MappingStore(defaults:upgradePrefs)
let removedFist=beforeCustomUpgrade.mappings.first { $0.gesture == .fist }!
beforeCustomUpgrade.remove(removedFist)
beforeCustomUpgrade.migrateDistinctTogglePreset()
check(beforeCustomUpgrade.mappings.contains(custom),"Migration preserves customised actions")
check(!beforeCustomUpgrade.mappings.contains { $0.gesture == .fist },"Migration does not recreate deleted mappings")
upgradePrefs.removePersistentDomain(forName:upgradeSuite)
print("Migration GestureChecks: \(count) checks passed")
