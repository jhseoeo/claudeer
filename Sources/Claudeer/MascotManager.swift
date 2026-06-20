import AppKit

class MascotManager {
    private var mascots: [String: Mascot] = [:]
    private let containerView: NSView
    private let assetStore: AssetStore
    private var areas: [CGRect] = []

    static let spriteSize = NSSize(width: 64, height: 64)

    init(containerView: NSView, assetStore: AssetStore) {
        self.containerView = containerView
        self.assetStore = assetStore
    }

    func setAreas(_ rects: [CGRect]) {
        self.areas = rects
        for mascot in mascots.values {
            mascot.characterController.setAreas(rects)
        }
    }

    @discardableResult
    func ensureMascot(sessionID: String) -> Mascot {
        if let existing = mascots[sessionID] { return existing }
        let mascot = Mascot(
            sessionID: sessionID,
            spriteSize: Self.spriteSize,
            initialPosition: randomInitialPosition(),
            container: containerView
        )
        mascot.spriteEngine.loadSprites(from: assetStore.spritesDirectory)
        mascot.spriteEngine.setFlips(assetStore.config.flips)
        mascot.characterController.setAreas(areas)
        mascot.characterController.setMovement(assetStore.config.movements)
        mascot.characterController.setSpeed(CGFloat(assetStore.config.speed))
        mascot.start()
        mascots[sessionID] = mascot
        return mascot
    }

    func removeMascot(sessionID: String) {
        guard let mascot = mascots.removeValue(forKey: sessionID) else { return }
        mascot.teardown()
    }

    func mascot(for sessionID: String) -> Mascot? {
        mascots[sessionID]
    }

    var allMascots: [Mascot] { Array(mascots.values) }

    var isEmpty: Bool { mascots.isEmpty }

    func reloadAssets() {
        for mascot in mascots.values {
            mascot.spriteEngine.loadSprites(from: assetStore.spritesDirectory)
            mascot.spriteEngine.setFlips(assetStore.config.flips)
            mascot.characterController.setMovement(assetStore.config.movements)
            mascot.characterController.setSpeed(CGFloat(assetStore.config.speed))
        }
    }

    func teardownAll() {
        for mascot in mascots.values {
            mascot.teardown()
        }
        mascots.removeAll()
    }

    private func randomInitialPosition() -> NSPoint {
        let spriteSize = Self.spriteSize
        let usable = areas.compactMap { rect -> CGRect? in
            let w = rect.width - spriteSize.width
            let h = rect.height - spriteSize.height
            return w >= 0 && h >= 0
                ? CGRect(x: rect.minX, y: rect.minY, width: w, height: h)
                : nil
        }
        guard let rect = usable.randomElement() else { return .zero }
        return NSPoint(
            x: CGFloat.random(in: rect.minX...max(rect.minX, rect.maxX)),
            y: CGFloat.random(in: rect.minY...max(rect.minY, rect.maxY))
        )
    }
}
