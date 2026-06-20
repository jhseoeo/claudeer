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
    private var currentPreset: AreaPreset = .bottom

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let store = AssetStore(baseDirectory: AssetStore.defaultBaseDirectory)
        assetStore = store

        mascotWindow = MascotWindow()

        let contentView = InteractionView(frame: NSRect(origin: .zero, size: mascotWindow!.frame.size))
        contentView.wantsLayer = true
        mascotWindow?.contentView = contentView

        soundPlayer = SoundPlayer()
        soundPlayer?.loadSounds(from: store.soundsDirectory)

        let manager = MascotManager(containerView: contentView, assetStore: store)
        mascotManager = manager
        currentPreset = AreaPreset(rawValue: store.config.defaultArea) ?? .bottom
        refreshAreas()

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
            self.refreshAreas()
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
        menuBarController?.currentPreset = currentPreset
        menuBarController?.onAreaChanged = { [weak self] preset in
            self?.currentPreset = preset
            self?.refreshAreas()
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        print("Claudeer started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        mascotManager?.teardownAll()
        eventServer?.stop()
        eventManager?.stopPIDMonitoring()
        interactionController?.stop()
    }

    @objc private func screensDidChange() {
        mascotWindow?.refreshFrameToAllScreens()
        refreshAreas()
    }

    private func refreshAreas() {
        guard let store = assetStore, let window = mascotWindow else { return }
        let active = NSScreen.screens(matching: store.config.targetScreenID)
        let globalRects = currentPreset.rects(for: active)
        let origin = window.frame.origin
        let localRects = globalRects.map { rect in
            CGRect(
                x: rect.minX - origin.x,
                y: rect.minY - origin.y,
                width: rect.width,
                height: rect.height
            )
        }
        mascotManager?.setAreas(localRects)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
