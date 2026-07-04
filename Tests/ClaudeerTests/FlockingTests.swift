import XCTest
import CoreGraphics
@testable import Claudeer

final class FlockingTests: XCTestCase {
    private func neighbor(_ x: CGFloat, _ y: CGFloat, vx: CGFloat = 0, vy: CGFloat = 0, engageable: Bool = false) -> NeighborState {
        NeighborState(center: CGPoint(x: x, y: y), velocity: CGVector(dx: vx, dy: vy), engageableForMeeting: engageable)
    }

    func testSeparationPushesAwayFromCloseNeighbor() {
        let f = Flocking.separation(center: CGPoint(x: 100, y: 100), neighbors: [neighbor(110, 100)], minDistance: 50)
        XCTAssertLessThan(f.dx, 0)   // neighbor is on the right → pushed left
        XCTAssertEqual(f.dy, 0, accuracy: 0.0001)
    }

    func testSeparationIgnoresFarNeighbor() {
        let f = Flocking.separation(center: CGPoint(x: 100, y: 100), neighbors: [neighbor(400, 100)], minDistance: 50)
        XCTAssertEqual(f.dx, 0, accuracy: 0.0001)
        XCTAssertEqual(f.dy, 0, accuracy: 0.0001)
    }

    func testCohesionPointsTowardGroupCentroid() {
        let f = Flocking.cohesion(center: CGPoint(x: 0, y: 0), neighbors: [neighbor(100, 0), neighbor(100, 100)], perception: 500)
        XCTAssertGreaterThan(f.dx, 0)
        XCTAssertGreaterThan(f.dy, 0)
    }

    func testCohesionIgnoresNeighborsOutsidePerception() {
        let f = Flocking.cohesion(center: CGPoint(x: 0, y: 0), neighbors: [neighbor(1000, 0)], perception: 100)
        XCTAssertEqual(f.dx, 0, accuracy: 0.0001)
        XCTAssertEqual(f.dy, 0, accuracy: 0.0001)
    }

    func testAlignmentPointsTowardMeanVelocity() {
        let f = Flocking.alignment(center: CGPoint(x: 0, y: 0), velocity: .zero,
                                   neighbors: [neighbor(10, 0, vx: 2), neighbor(0, 10, vx: 2)], perception: 500)
        XCTAssertGreaterThan(f.dx, 0)
        XCTAssertEqual(f.dy, 0, accuracy: 0.0001)
    }

    func testCursorSeekNilOutsideRadius() {
        XCTAssertNil(Flocking.cursorSeek(center: CGPoint(x: 0, y: 0), cursor: CGPoint(x: 300, y: 0), radius: 250))
    }

    func testCursorSeekUnitVectorTowardCursorInsideRadius() {
        let f = Flocking.cursorSeek(center: CGPoint(x: 0, y: 0), cursor: CGPoint(x: 100, y: 0), radius: 250)
        XCTAssertNotNil(f)
        XCTAssertEqual(f!.dx, 1, accuracy: 0.0001)
        XCTAssertEqual(f!.dy, 0, accuracy: 0.0001)
    }

    func testNearestMeetTargetPicksClosestEngageable() {
        let t = Flocking.nearestMeetTarget(center: CGPoint(x: 0, y: 0),
                                           neighbors: [neighbor(40, 0, engageable: true), neighbor(20, 0, engageable: true)],
                                           meetDistance: 48)
        XCTAssertEqual(t?.x, 20)
    }

    func testNearestMeetTargetIgnoresNonEngageable() {
        let t = Flocking.nearestMeetTarget(center: CGPoint(x: 0, y: 0),
                                           neighbors: [neighbor(20, 0, engageable: false)], meetDistance: 48)
        XCTAssertNil(t)
    }

    func testNearestMeetTargetNilWhenOutOfRange() {
        let t = Flocking.nearestMeetTarget(center: CGPoint(x: 0, y: 0),
                                           neighbors: [neighbor(100, 0, engageable: true)], meetDistance: 48)
        XCTAssertNil(t)
    }

    func testSteerCapsToMaxSpeed() {
        let v = Flocking.steer(base: CGVector(dx: 10, dy: 0), forces: [], maxSpeed: 2)
        XCTAssertEqual((v.dx * v.dx + v.dy * v.dy).squareRoot(), 2, accuracy: 0.0001)
    }

    func testSteerAddsWeightedForces() {
        let v = Flocking.steer(base: CGVector(dx: 1, dy: 0), forces: [(CGVector(dx: 0, dy: 1), 2)], maxSpeed: 100)
        XCTAssertEqual(v.dx, 1, accuracy: 0.0001)
        XCTAssertEqual(v.dy, 2, accuracy: 0.0001)
    }
}
