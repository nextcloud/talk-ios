//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

@objcMembers class NCNavigationController: UINavigationController, UIGestureRecognizerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        self.interactivePopGestureRecognizer?.delegate = self
        NCAppBranding.styleViewController(self)
        self.view.backgroundColor = .clear
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        if #available(iOS 26, *) {
            return .default
        }

        return NCAppBranding.statusBarStyleForThemeColor()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // This allows to overwrite the pop gesture recognizer with another gesture recognizer
        // (e.g. long press gesture to record voice message when interface is in RTL)
        return true
    }

}
