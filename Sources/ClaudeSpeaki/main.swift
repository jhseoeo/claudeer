import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var mascotWindow: MascotWindow?
    var spriteEngine: SpriteEngine?
    var characterController: CharacterController?
    var eventServer: EventServer?
    var eventManager: EventManager?
    var soundPlayer: SoundPlayer?
    var speechBubble: SpeechBubbleView?
    var config: SpeakiConfig = .default
    var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Load config
        if let configURL = Bundle.module.url(forResource: "Resources", withExtension: nil)?
            .appendingPathComponent("config.json") {
            config = SpeakiConfig.load(from: configURL)
        }

        // Setup window
        mascotWindow = MascotWindow()

        let contentView = NSView(frame: mascotWindow!.frame)
        contentView.wantsLayer = true

        // Setup sprite
        let spriteSize = NSRect(x: 100, y: 100, width: 64, height: 64)
        spriteEngine = SpriteEngine(frame: spriteSize)
        contentView.addSubview(spriteEngine!.view)

        // Setup speech bubble
        speechBubble = SpeechBubbleView()
        speechBubble?.isHidden = true
        contentView.addSubview(speechBubble!)

        mascotWindow?.contentView = contentView

        // Load resources
        if let resourceURL = Bundle.module.url(forResource: "Resources", withExtension: nil) {
            spriteEngine?.loadSprites(from: resourceURL.appendingPathComponent("sprites"))

            soundPlayer = SoundPlayer()
            soundPlayer?.loadSounds(from: resourceURL.appendingPathComponent("sounds"))
        }

        // Setup movement
        characterController = CharacterController(spriteEngine: spriteEngine!)
        if let screen = NSScreen.main {
            let preset = AreaPreset(rawValue: config.defaultArea) ?? .bottom
            characterController?.setArea(preset, screenSize: screen.frame.size)
        }
        characterController?.start()

        // Setup event manager
        eventManager = EventManager(
            characterController: characterController!,
            soundPlayer: soundPlayer ?? SoundPlayer(),
            speechBubble: speechBubble!,
            spriteEngine: spriteEngine!,
            config: config
        )
        eventManager?.startPIDMonitoring()

        // Start socket server
        eventServer = EventServer()
        eventServer?.onEvent = { [weak self] event in
            self?.eventManager?.handleEvent(event)
        }
        eventServer?.start()

        // Setup menu bar
        menuBarController = MenuBarController()
        menuBarController?.currentPreset = AreaPreset(rawValue: config.defaultArea) ?? .bottom
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
        print("Claude Speaki started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        characterController?.stop()
        eventServer?.stop()
        eventManager?.stopPIDMonitoring()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
