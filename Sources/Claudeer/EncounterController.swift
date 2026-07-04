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
/// new encounter until it passes. Pure coordination: it reads mascot centers and
/// pushes `InteractionDirective`s; it owns no UI and no per-mascot movement.
final class EncounterController {
    struct Tuning {
        var encounterDistance: CGFloat = 180   // wanderers this close can start an encounter
        var cuddleDistance: CGFloat = 80       // a member is "gathered" within this of the center
        var cuddleDuration: TimeInterval = 3.0
        var disperseDuration: TimeInterval = 1.5
        var gatherTimeout: TimeInterval = 6.0  // give up gathering if it drags on
        var socialCooldown: TimeInterval = 60.0   // after an encounter a mascot won't join ANY new one for this long
        var maxGroup: Int = 6
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

        // 1) Advance active encounters.
        var stillActive: [Encounter] = []
        for e in encounters {
            e.members = e.members.filter { byId[$0]?.available == true }
            if e.members.count < 2 {
                for m in e.members { byId[m]?.controller.clearInteraction() }
                continue   // disbanded before cuddling — no pair recorded
            }
            let centers = e.members.compactMap { byId[$0]?.center }
            e.center = CGPoint(x: centers.map { $0.x }.reduce(0, +) / CGFloat(centers.count),
                               y: centers.map { $0.y }.reduce(0, +) / CGFloat(centers.count))
            e.phaseElapsed += dt

            switch e.phase {
            case .gather:
                push(e, mode: .gather, byId: byId)
                let gathered = e.members.allSatisfy { id in
                    guard let c = byId[id]?.center else { return false }
                    return hypot(c.x - e.center.x, c.y - e.center.y) <= tuning.cuddleDistance
                }
                if gathered || e.phaseElapsed >= tuning.gatherTimeout {
                    e.phase = .cuddle
                    e.phaseElapsed = 0
                }
            case .cuddle:
                push(e, mode: .cuddle, byId: byId)
                if e.phaseElapsed >= tuning.cuddleDuration {
                    e.phase = .disperse
                    e.phaseElapsed = 0
                }
            case .disperse:
                push(e, mode: .disperse, byId: byId)
                if e.phaseElapsed >= tuning.disperseDuration {
                    recordMet(e.members)
                    for m in e.members { byId[m]?.controller.clearInteraction() }
                    continue   // encounter complete
                }
            }
            stillActive.append(e)
        }
        encounters = stillActive

        // 2) Form new encounters from free mascots that are off social cooldown.
        let busy = Set(encounters.flatMap { $0.members })
        let free = participants.filter { $0.available && !busy.contains($0.id) && offCooldown($0.id) }
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

    private func push(_ e: Encounter, mode: InteractionDirective.Mode, byId: [String: EncounterParticipant]) {
        for m in e.members {
            byId[m]?.controller.setInteraction(InteractionDirective(mode: mode, focus: e.center))
        }
    }

    private func recordMet(_ members: [String]) {
        for m in members { lastEncountered[m] = clock }
    }

    private func releaseAll() {
        for e in encounters {
            for m in e.members { manager?.controller(for: m)?.clearInteraction() }
        }
        encounters.removeAll()
    }
}
