import AppKit

/// A directive the `EncounterController` pushes onto a `CharacterController`
/// each tick while that mascot is in a social encounter.
struct InteractionDirective {
    enum Mode { case gather, cuddle, disperse }
    let mode: Mode
    /// The encounter's focus point (group centroid) in global screen coordinates.
    let focus: CGPoint
}

/// One mascot's state as seen by the coordinator.
struct EncounterParticipant {
    let id: String
    let controller: CharacterController
    let center: CGPoint
    let available: Bool
}

/// Drives *episodic* social encounters: nearby idle mascots that are off social
/// cooldown gather into a group, cuddle for a few seconds, then disperse — after
/// which each participant is on a per-mascot `socialCooldown` and won't join any
/// new encounter until it passes. Groups grow while an encounter is live: any
/// free wanderer that passes within `joinRadius` joins in, so gatherings snowball
/// past the initial pair. Pure coordination — it reads mascot centers and pushes
/// `InteractionDirective`s; it owns no UI and no per-mascot movement.
final class EncounterController {
    struct Tuning {
        var encounterDistance: CGFloat = 260   // two wanderers this close can START an encounter
        var joinRadius: CGFloat = 600          // a wanderer this close to a LIVE encounter joins it
        var cuddleDistance: CGFloat = 84       // a member counts as gathered/cuddling within this of the center
        var cuddleDuration: TimeInterval = 3.0
        var disperseDuration: TimeInterval = 1.5
        var gatherTimeout: TimeInterval = 6.0  // give up gathering if it drags on
        var socialCooldown: TimeInterval = 60.0
        var maxGroup: Int = 8
    }

    var tuning = Tuning()
    var enabled = false

    private weak var manager: MascotManager?
    private var timer: Timer?
    private var clock: TimeInterval = 0

    private enum Phase { case gather, cuddle, disperse }
    private final class Encounter {
        var members: [String]
        var phase: Phase = .gather
        var phaseElapsed: TimeInterval = 0
        var center: CGPoint = .zero
        var hearts: Set<String> = []   // members currently showing a ❤️
        init(_ members: [String]) { self.members = members }
    }
    private var encounters: [Encounter] = []
    private var lastEncountered: [String: TimeInterval] = [:]   // mascot id -> clock it last finished an encounter

    init(manager: MascotManager) {
        self.manager = manager
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick(dt: 1.0 / 30.0)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// A mascot can join a new encounter only after its social cooldown elapses.
    private func offCooldown(_ id: String) -> Bool {
        guard let t = lastEncountered[id] else { return true }
        return clock - t >= tuning.socialCooldown
    }

    private func tick(dt: TimeInterval) {
        clock += dt
        guard enabled, let manager = manager else {
            if !encounters.isEmpty { releaseAll() }
            return
        }

        let participants = manager.encounterParticipants()
        let byId = Dictionary(participants.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var claimed = Set(encounters.flatMap { $0.members })

        // 1) Advance (and grow) active encounters.
        var stillActive: [Encounter] = []
        for e in encounters {
            e.members = e.members.filter { byId[$0]?.available == true }
            if e.members.count < 2 {
                endEncounter(e, byId: byId, recordMet: false)
                continue
            }
            recenter(e, byId: byId)

            // Snowball: nearby free wanderers join a live gathering/cuddle.
            if e.phase != .disperse && e.members.count < tuning.maxGroup {
                for p in participants
                    where p.available && offCooldown(p.id)
                        && !claimed.contains(p.id) && !e.members.contains(p.id) {
                    if hypot(p.center.x - e.center.x, p.center.y - e.center.y) <= tuning.joinRadius {
                        e.members.append(p.id)
                        claimed.insert(p.id)
                        if e.members.count >= tuning.maxGroup { break }
                    }
                }
                recenter(e, byId: byId)
            }

            e.phaseElapsed += dt
            switch e.phase {
            case .gather:
                let gathered = e.members.allSatisfy { id in
                    guard let c = byId[id]?.center else { return false }
                    return hypot(c.x - e.center.x, c.y - e.center.y) <= tuning.cuddleDistance
                }
                if gathered || e.phaseElapsed >= tuning.gatherTimeout {
                    e.phase = .cuddle
                    e.phaseElapsed = 0
                }
            case .cuddle:
                if e.phaseElapsed >= tuning.cuddleDuration {
                    e.phase = .disperse
                    e.phaseElapsed = 0
                }
            case .disperse:
                if e.phaseElapsed >= tuning.disperseDuration {
                    endEncounter(e, byId: byId, recordMet: true)
                    continue
                }
            }
            drive(e, byId: byId)
            stillActive.append(e)
        }
        encounters = stillActive

        // 1b) Merge encounters that have drifted close, so several small gatherings
        // coalesce into one bigger 우르르 instead of staying separate pairs.
        var didMerge = true
        while didMerge {
            didMerge = false
            outer: for i in 0..<encounters.count {
                for j in (i + 1)..<encounters.count {
                    let a = encounters[i], b = encounters[j]
                    guard a.phase != .disperse, b.phase != .disperse,
                          a.members.count + b.members.count <= tuning.maxGroup,
                          hypot(a.center.x - b.center.x, a.center.y - b.center.y) <= tuning.joinRadius
                    else { continue }
                    a.members.append(contentsOf: b.members)
                    a.hearts.formUnion(b.hearts)   // carried over so drive() can reconcile them
                    a.phase = .gather               // re-gather the combined group
                    a.phaseElapsed = 0
                    recenter(a, byId: byId)
                    encounters.remove(at: j)
                    didMerge = true
                    break outer
                }
            }
        }

        // 2) Form new encounters from unclaimed, off-cooldown wanderers.
        let free = participants.filter { $0.available && !claimed.contains($0.id) && offCooldown($0.id) }
        var used = Set<String>()
        for seed in free where !used.contains(seed.id) {
            var group = [seed.id]
            for other in free where other.id != seed.id && !used.contains(other.id) {
                guard group.count < tuning.maxGroup else { break }
                if hypot(other.center.x - seed.center.x, other.center.y - seed.center.y) <= tuning.encounterDistance {
                    group.append(other.id)
                }
            }
            if group.count >= 2 {
                encounters.append(Encounter(group))
                used.formUnion(group)
            }
        }
    }

    private func recenter(_ e: Encounter, byId: [String: EncounterParticipant]) {
        let centers = e.members.compactMap { byId[$0]?.center }
        guard !centers.isEmpty else { return }
        e.center = CGPoint(x: centers.map { $0.x }.reduce(0, +) / CGFloat(centers.count),
                           y: centers.map { $0.y }.reduce(0, +) / CGFloat(centers.count))
    }

    /// Push per-member directives and reconcile ❤️ — shown only for members
    /// actually cuddling (close to the center during the cuddle phase), so late
    /// joiners keep gathering (and get their heart) once they arrive.
    private func drive(_ e: Encounter, byId: [String: EncounterParticipant]) {
        var cuddling = Set<String>()
        for m in e.members {
            guard let c = byId[m]?.center else { continue }
            let mode: InteractionDirective.Mode
            switch e.phase {
            case .gather:
                mode = .gather
            case .disperse:
                mode = .disperse
            case .cuddle:
                if hypot(c.x - e.center.x, c.y - e.center.y) <= tuning.cuddleDistance {
                    mode = .cuddle
                    cuddling.insert(m)
                } else {
                    mode = .gather
                }
            }
            byId[m]?.controller.setInteraction(InteractionDirective(mode: mode, focus: e.center))
        }
        for m in cuddling.subtracting(e.hearts) { manager?.mascot(for: m)?.showHeart() }
        for m in e.hearts.subtracting(cuddling) { manager?.mascot(for: m)?.hideHeart() }
        e.hearts = cuddling
    }

    private func endEncounter(_ e: Encounter, byId: [String: EncounterParticipant], recordMet: Bool) {
        for m in e.members {
            byId[m]?.controller.clearInteraction()
            manager?.mascot(for: m)?.hideHeart()
        }
        e.hearts.removeAll()
        if recordMet {
            for m in e.members { lastEncountered[m] = clock }
        }
    }

    private func releaseAll() {
        for e in encounters {
            for m in e.members {
                manager?.controller(for: m)?.clearInteraction()
                manager?.mascot(for: m)?.hideHeart()
            }
        }
        encounters.removeAll()
    }
}
