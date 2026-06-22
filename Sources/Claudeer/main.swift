import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var overlayController: OverlayWindowController?
    var mascotManager: MascotManager?
    var eventServer: EventServer?
    var eventManager: EventManager?
    var soundPlayer: SoundPlayer?
    var menuBarController: MenuBarController?
    var assetStore: AssetStore?
    var interactionController: InteractionController?
    private var cancellables = Set<AnyCancellable>()
    private var currentPreset: AreaPreset = .bottom
    private var currentTargetScreenID: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let store = AssetStore(baseDirectory: AssetStore.defaultBaseDirectory)
        assetStore = store

        let overlay = OverlayWindowController()
        overlayController = overlay

        soundPlayer = SoundPlayer()
        soundPlayer?.loadSounds(from: store.soundsDirectory)

        let manager = MascotManager(placer: overlay, assetStore: store)
        mascotManager = manager
        currentPreset = AreaPreset(rawValue: store.config.defaultArea) ?? .bottom

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
            if self.currentTargetScreenID != store.config.targetScreenID {
                self.currentTargetScreenID = store.config.targetScreenID
                self.overlayController?.configure(targetScreenID: store.config.targetScreenID)
            }
            self.refreshAreas()
        }

        interactionController = InteractionController(
            overlay: overlay,
            mascotManager: manager,
            soundPlayer: soundPlayer!
        )
        interactionController?.onMascotDoubleClicked = { mascot in
            guard let pid = sessionTracker.pid(for: mascot.sessionID) else { return }
            let cwd = sessionTracker.cwd(for: mascot.sessionID)
            // Off the main thread: the off-Space window search can take a few
            // hundred ms. Running async also defers past AppKit's post-click
            // activation handling, which would otherwise clobber the focus.
            DispatchQueue.global(qos: .userInitiated).async {
                WindowFocuser.focus(pid: pid, cwd: cwd)
            }
        }

        // Build the overlay windows (one per active screen) with the interaction
        // delegate wired, then lay out roaming areas in global coordinates.
        currentTargetScreenID = store.config.targetScreenID
        overlay.configure(targetScreenID: currentTargetScreenID)
        refreshAreas()
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
                guard let overlay = self?.overlayController else { return }
                if sessions.isEmpty {
                    overlay.hideAll()
                } else {
                    overlay.showAll()
                }
            }
            .store(in: &cancellables)

        sessionTracker.$hiddenSessionIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ids in
                self?.mascotManager?.setHidden(ids)
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
        overlayController?.rebuild()
        refreshAreas()
    }

    private func refreshAreas() {
        guard let store = assetStore else { return }
        let active = NSScreen.screens(matching: store.config.targetScreenID)
        let globalRects = currentPreset.rects(for: active)
        mascotManager?.setAreas(globalRects)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
