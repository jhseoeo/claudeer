import CoreGraphics

/// A snapshot of another mascot in global screen coordinates, used to compute
/// flocking forces. Pure data — no AppKit/UI dependency, so it is unit-testable.
struct NeighborState {
    let center: CGPoint
    let velocity: CGVector
    /// Idle and not paused/frozen/dragging/hidden/meeting — eligible to be greeted.
    let engageableForMeeting: Bool
}

/// Stateless steering-force math for the mascot flock. All vectors are in global
/// screen coordinates. Kept AppKit-free so it can be unit-tested directly.
enum Flocking {
    /// Steer away from neighbors closer than `minDistance`; strength grows as a
    /// neighbor gets closer. Returns a vector pointing away from the crowd.
    static func separation(center: CGPoint, neighbors: [NeighborState], minDistance: CGFloat) -> CGVector {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        for n in neighbors {
            let ox = center.x - n.center.x
            let oy = center.y - n.center.y
            let dist = (ox * ox + oy * oy).squareRoot()
            if dist > 0 && dist < minDistance {
                let falloff = (minDistance - dist) / minDistance
                dx += ox / dist * falloff
                dy += oy / dist * falloff
            }
        }
        return CGVector(dx: dx, dy: dy)
    }

    /// Steer toward the average position of neighbors within `perception`.
    /// Returns a unit vector (or zero when there are no neighbors in range).
    static func cohesion(center: CGPoint, neighbors: [NeighborState], perception: CGFloat) -> CGVector {
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var count: CGFloat = 0
        for n in neighbors {
            let dx = n.center.x - center.x
            let dy = n.center.y - center.y
            if (dx * dx + dy * dy).squareRoot() < perception {
                sumX += n.center.x
                sumY += n.center.y
                count += 1
            }
        }
        guard count > 0 else { return .zero }
        return normalized(CGVector(dx: sumX / count - center.x, dy: sumY / count - center.y))
    }

    /// Steer toward the average velocity (heading) of neighbors within `perception`.
    /// Returns a unit vector (or zero when there are no neighbors in range).
    static func alignment(center: CGPoint, velocity: CGVector, neighbors: [NeighborState], perception: CGFloat) -> CGVector {
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var count: CGFloat = 0
        for n in neighbors {
            let dx = n.center.x - center.x
            let dy = n.center.y - center.y
            if (dx * dx + dy * dy).squareRoot() < perception {
                sumX += n.velocity.dx
                sumY += n.velocity.dy
                count += 1
            }
        }
        guard count > 0 else { return .zero }
        return normalized(CGVector(dx: sumX / count, dy: sumY / count))
    }

    /// Unit vector toward `cursor` when within `radius` of `center`; nil otherwise.
    static func cursorSeek(center: CGPoint, cursor: CGPoint, radius: CGFloat) -> CGVector? {
        let dx = cursor.x - center.x
        let dy = cursor.y - center.y
        let dist = (dx * dx + dy * dy).squareRoot()
        guard dist <= radius else { return nil }
        guard dist > 0 else { return .zero }
        return CGVector(dx: dx / dist, dy: dy / dist)
    }

    /// The center of the closest engageable neighbor within `meetDistance`, or nil.
    static func nearestMeetTarget(center: CGPoint, neighbors: [NeighborState], meetDistance: CGFloat) -> CGPoint? {
        var best: CGPoint?
        var bestDist = meetDistance
        for n in neighbors where n.engageableForMeeting {
            let dx = n.center.x - center.x
            let dy = n.center.y - center.y
            let dist = (dx * dx + dy * dy).squareRoot()
            if dist < bestDist {
                bestDist = dist
                best = n.center
            }
        }
        return best
    }

    /// Sum `base` with each weighted force, then clamp the result to `maxSpeed`.
    static func steer(base: CGVector, forces: [(CGVector, CGFloat)], maxSpeed: CGFloat) -> CGVector {
        var vx = base.dx
        var vy = base.dy
        for (f, w) in forces {
            vx += f.dx * w
            vy += f.dy * w
        }
        let mag = (vx * vx + vy * vy).squareRoot()
        if mag > maxSpeed && mag > 0 {
            vx = vx / mag * maxSpeed
            vy = vy / mag * maxSpeed
        }
        return CGVector(dx: vx, dy: vy)
    }

    /// A unit vector in the direction of `v`, or zero if `v` has zero magnitude.
    static func normalized(_ v: CGVector) -> CGVector {
        let mag = (v.dx * v.dx + v.dy * v.dy).squareRoot()
        guard mag > 0 else { return .zero }
        return CGVector(dx: v.dx / mag, dy: v.dy / mag)
    }
}
