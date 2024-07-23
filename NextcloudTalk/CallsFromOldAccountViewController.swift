//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class CallsFromOldAccountViewController: UIViewController {

    @IBOutlet weak var warningTextLabel: UILabel!
    @IBOutlet weak var acknowledgeWarningButton: NCButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Calls from old accounts", comment: "")

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        appearance.backgroundColor = NCAppBranding.themeColor()
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

        acknowledgeWarningButton.setTitle(NSLocalizedString("Confirm and hide warning", comment: ""), for: .normal)
        acknowledgeWarningButton.setButtonStyle(style: .primary)

        let warning1 = NSLocalizedString("Calls from an old account were received.", comment: "")
        let warning2 = NSLocalizedString("This usually indicates that this device was previously used for an account, which was not properly removed from the server.", comment: "")
        let warning3 = NSLocalizedString("To resolve this issue, use the web interface and go to \"Settings -> Security\".", comment: "")
        let warning4 = NSLocalizedString("Under \"Devices & sessions\" check if there are duplicate entries for the same device.", comment: "")
        let warning5 = NSLocalizedString("Remove old duplicate entries and leave only the most recent entries.", comment: "")
        let warning6 = NSLocalizedString("If you're using multiple servers, you need to check all of them.", comment: "")

        let warningTextComplete = warning1 + " " + warning2 + "\n\n" + warning3 + "\n\n" + warning4 + "\n\n" + warning5 + "\n\n" + warning6

        warningTextLabel.text = warningTextComplete
    }

    @IBAction func acknowledgeWarningButtonPressed(_ sender: Any) {
        NCSettingsController.sharedInstance().setDidReceiveCallsFromOldAccount(false)
        self.navigationController?.popViewController(animated: true)
    }

}
