import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var mascotWindow: MascotWindow?
    var mascotManager: MascotManager?
    var eventServer: EventServer?
    var eventManager: EventManager?
    var soundPlayer: SoundPlayer?
    var menuBarController: MenuBarController?
    var assetStore: AssetStore?
    var interactionController: InteractionController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let store = AssetStore(baseDirectory: AssetStore.defaultBaseDirectory)
        assetStore = store

        mascotWindow = MascotWindow()

        let contentView = InteractionView(frame: mascotWindow!.frame)
        contentView.wantsLayer = true
        mascotWindow?.contentView = contentView

        soundPlayer = SoundPlayer()
        soundPlayer?.loadSounds(from: store.soundsDirectory)

        let manager = MascotManager(containerView: contentView, assetStore: store)
        mascotManager = manager
        if let screen = NSScreen.main {
            let preset = AreaPreset(rawValue: store.config.defaultArea) ?? .bottom
            manager.setArea(preset, screenSize: screen.frame.size)
        }

        let sessionTracker = SessionTracker()
        eventManager = EventManager(
            mascotManager: manager,
            soundPlayer: soundPlayer!,
            sessionTracker: sessionTracker,
            config: store.config
        )
        eventManager?.startPIDMonitoring()
        eventManager?.syncLoop()

        store.onAssetsChanged = { [weak self] in
            guard let self = self, let store = self.assetStore else { return }
            self.mascotManager?.reloadAssets()
            self.soundPlayer?.loadSounds(from: store.soundsDirectory)
            self.eventManager?.config = store.config
            self.eventManager?.syncLoop()
        }

        interactionController = InteractionController(
            window: mascotWindow!,
            interactionView: contentView,
            mascotManager: manager,
            soundPlayer: soundPlayer!
        )
        interactionController?.start()

        eventServer = EventServer()
        eventServer?.onEvent = { [weak self] event in
            self?.eventManager?.handleEvent(event)
        }
        eventServer?.start()

        menuBarController = MenuBarController()
        menuBarController?.assetStore = store
        menuBarController?.sessionTracker = sessionTracker
        menuBarController?.currentPreset = AreaPreset(rawValue: store.config.defaultArea) ?? .bottom
        menuBarController?.onAreaChanged = { [weak self] preset in
            if let screen = NSScreen.main {
                self?.mascotManager?.setArea(preset, screenSize: screen.frame.size)
            }
        }
        menuBarController?.onVolumeChanged = { [weak self] volume in
            self?.soundPlayer?.volume = volume
        }
        menuBarController?.setup()

        sessionTracker.$sessions
            .sink { [weak self] sessions in
                guard let window = self?.mascotWindow else { return }
                if sessions.isEmpty {
                    window.orderOut(nil)
                } else if !window.isVisible {
                    window.orderFront(nil)
                }
            }
            .store(in: &cancellables)

        print("Claudeer started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        mascotManager?.teardownAll()
        eventServer?.stop()
        eventManager?.stopPIDMonitoring()
        interactionController?.stop()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
