import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var mascotWindow: MascotWindow?
    var spriteEngine: SpriteEngine?
    var characterController: CharacterController?
    var eventServer: EventServer?
    var eventManager: EventManager?
    var soundPlayer: SoundPlayer?
    var speechBubble: SpeechBubbleView?
    var menuBarController: MenuBarController?
    var assetStore: AssetStore?
    var interactionController: InteractionController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let store = AssetStore(baseDirectory: AssetStore.defaultBaseDirectory)
        assetStore = store

        mascotWindow = MascotWindow()

        let contentView = InteractionView(frame: mascotWindow!.frame)
        contentView.wantsLayer = true

        let spriteSize = NSRect(x: 100, y: 100, width: 64, height: 64)
        spriteEngine = SpriteEngine(frame: spriteSize)
        contentView.addSubview(spriteEngine!.view)

        speechBubble = SpeechBubbleView()
        speechBubble?.isHidden = true
        contentView.addSubview(speechBubble!)

        mascotWindow?.contentView = contentView

        spriteEngine?.loadSprites(from: store.spritesDirectory)
        soundPlayer = SoundPlayer()
        soundPlayer?.loadSounds(from: store.soundsDirectory)

        characterController = CharacterController(spriteEngine: spriteEngine!)
        if let screen = NSScreen.main {
            let preset = AreaPreset(rawValue: store.config.defaultArea) ?? .bottom
            characterController?.setArea(preset, screenSize: screen.frame.size)
        }
        characterController?.setMovement(store.config.movements)
        characterController?.setSpeed(CGFloat(store.config.speed))
        characterController?.start()

        eventManager = EventManager(
            characterController: characterController!,
            soundPlayer: soundPlayer!,
            speechBubble: speechBubble!,
            spriteEngine: spriteEngine!,
            sessionTracker: SessionTracker(),
            config: store.config
        )
        eventManager?.startPIDMonitoring()
        eventManager?.syncLoop()

        store.onAssetsChanged = { [weak self] in
            guard let self = self, let store = self.assetStore else { return }
            self.spriteEngine?.loadSprites(from: store.spritesDirectory)
            self.soundPlayer?.loadSounds(from: store.soundsDirectory)
            self.eventManager?.config = store.config
            self.eventManager?.syncLoop()
            self.characterController?.setMovement(store.config.movements)
            self.characterController?.setSpeed(CGFloat(store.config.speed))
        }

        interactionController = InteractionController(
            window: mascotWindow!,
            interactionView: contentView,
            spriteEngine: spriteEngine!,
            soundPlayer: soundPlayer!,
            characterController: characterController!
        )
        interactionController?.start()

        eventServer = EventServer()
        eventServer?.onEvent = { [weak self] event in
            self?.eventManager?.handleEvent(event)
        }
        eventServer?.start()

        menuBarController = MenuBarController()
        menuBarController?.assetStore = store
        menuBarController?.sessionTracker = eventManager?.sessionTracker
        menuBarController?.currentPreset = AreaPreset(rawValue: store.config.defaultArea) ?? .bottom
        menuBarController?.onAreaChanged = { [weak self] preset in
            if let screen = NSScreen.main {
                self?.characterController?.setArea(preset, screenSize: screen.frame.size)
            }
        }
        menuBarController?.onVolumeChanged = { [weak self] volume in
            self?.soundPlayer?.volume = volume
        }
        menuBarController?.setup()

        mascotWindow?.makeKeyAndOrderFront(nil)
        print("Claudeer started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        characterController?.stop()
        eventServer?.stop()
        eventManager?.stopPIDMonitoring()
        interactionController?.stop()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
