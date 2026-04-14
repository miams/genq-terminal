import Sparkle
import Cocoa

extension UpdateDriver: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            return nil
        }

        // GenQuery publishes arch-specific appcast files as GitHub Release assets.
        // We select the right one at compile time so Sparkle always downloads
        // the DMG that matches the running architecture.
        #if arch(arm64)
        let archSuffix = "arm64"
        #else
        let archSuffix = "x86_64"
        #endif
        let base = "https://github.com/miams/genq/releases/latest/download"
        switch appDelegate.ghostty.config.autoUpdateChannel {
        case .tip:    return "\(base)/appcast-\(archSuffix).xml"
        case .stable: return "\(base)/appcast-\(archSuffix).xml"
        }
    }

    /// Called when an update is scheduled to install silently,
    /// which occurs when `auto-update = download`.
    ///
    /// When `auto-update = check`, Sparkle will call the corresponding
    /// delegate method on the responsible driver instead.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        viewModel.state = .installing(.init(
            isAutoUpdate: true,
            retryTerminatingApplication: immediateInstallHandler,
            dismiss: { [weak viewModel] in
                viewModel?.state = .idle
            }
        ))
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        // When the updater is relaunching the application we want to get macOS
        // to invalidate and re-encode all of our restorable state so that when
        // we relaunch it uses it.
        NSApp.invalidateRestorableState()
        for window in NSApp.windows { window.invalidateRestorableState() }
    }
}
