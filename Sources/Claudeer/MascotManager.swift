import AppKit

class MascotManager {
    private var mascots: [String: Mascot] = [:]
    private let containerView: NSView
    private let assetStore: AssetStore
    private var areaPreset: AreaPreset = .bottom
    private var screenSize: CGSize = .zero

    static let spriteSize = NSSize(width: 64, height: 64)

    init(containerView: NSView, assetStore: AssetStore) {
        self.containerView = containerView
        self.assetStore = assetStore
    }

    func setArea(_ preset: AreaPreset, screenSize: CGSize) {
        self.areaPreset = preset
        self.screenSize = screenSize
        for mascot in mascots.values {
            mascot.characterController.setArea(preset, screenSize: screenSize)
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
        mascot.characterController.setArea(areaPreset, screenSize: screenSize)
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
        let rect = areaPreset.rect(for: screenSize)
        let minX = rect.minX
        let maxX = rect.maxX - Self.spriteSize.width
        let minY = rect.minY
        let maxY = rect.maxY - Self.spriteSize.height
        return NSPoint(
            x: CGFloat.random(in: minX...max(minX, maxX)),
            y: CGFloat.random(in: minY...max(minY, maxY))
        )
    }
}
