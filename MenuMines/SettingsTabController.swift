import AppKit
import SwiftUI

/// Settings as a Mac app's settings window: a toolbar of pages, the window titled for the page
/// that's up, and its height following the page, top edge pinned.
@MainActor
final class SettingsTabController: NSTabViewController {
    /// The page Settings showed last, which it opens to again for the rest of the session.
    static var lastPage: SettingsPage = .general

    /// The page Settings opens to: the last one, if this build still has it.
    static var openingPage: SettingsPage {
        SettingsPage.available.contains(lastPage) ? lastPage : .general
    }

    var selectedPage: SettingsPage? {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return nil }
        return (tabViewItems[selectedTabViewItemIndex].identifier as? String).flatMap(SettingsPage.init(rawValue:))
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar

        for page in SettingsPage.available {
            let host = NSHostingController(rootView: SettingsView(page: page))
            // The form scrolls and so reports no height of its own; the window's size is ours.
            host.sizingOptions = []
            // The window takes its title from the page that's up.
            host.title = page.title
            let item = NSTabViewItem(viewController: host)
            item.identifier = page.rawValue
            item.label = page.title
            item.image = NSImage(systemSymbolName: page.symbolName, accessibilityDescription: nil)
            addTabViewItem(item)
        }

        if let index = SettingsPage.available.firstIndex(of: Self.openingPage) {
            selectedTabViewItemIndex = index
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // The toolbar is only in once the window is up.
        fitWindow()
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let page = selectedPage else { return }
        Self.lastPage = page
        fitWindow()
    }

    private func fitWindow() {
        guard let page = selectedPage, let window = view.window else { return }
        AppWindows.fit(window, toContentHeight: SettingsView.idealContentSize(for: page).height)
    }
}
