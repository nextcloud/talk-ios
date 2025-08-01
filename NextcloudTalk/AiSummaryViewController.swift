//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class AiSummaryViewController: UIViewController {

    private var summaryText: String = ""

    @IBOutlet weak var warningView: UIView!
    @IBOutlet weak var warningTextLabel: UILabel!
    @IBOutlet weak var saveToNoteToSelf: NCButton!
    @IBOutlet weak var summaryTextView: UITextView!

    init(summaryText: String) {
        self.summaryText = summaryText

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        let barButtonItem = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        barButtonItem.primaryAction = UIAction(title: NSLocalizedString("Close", comment: ""), handler: { [unowned self] _ in
            self.dismiss(animated: true)
        })
        self.navigationItem.rightBarButtonItems = [barButtonItem]

        saveToNoteToSelf.setTitle(NSLocalizedString("Save to 'Note to self'", comment: ""), for: .normal)
        saveToNoteToSelf.setButtonStyle(style: .primary)

        warningView.layer.cornerRadius = 8
        warningView.layer.borderColor = NCAppBranding.placeholderColor().cgColor
        warningView.layer.borderWidth = 1
        warningView.layer.masksToBounds = true

        warningTextLabel.text = NSLocalizedString("This summary is AI generated and may contain mistakes.", comment: "")

        summaryTextView.text = self.summaryText
    }

    @IBAction func saveToNoteToSelfPressed(_ sender: Any) {
        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()

        self.saveToNoteToSelf.setButtonEnabled(enabled: false)

        NCAPIController.sharedInstance().getNoteToSelfRoom(forAccount: activeAccount) { roomDict, error in
            if error == nil, let room = NCRoom(dictionary: roomDict, andAccountId: activeAccount.accountId) {

                NCAPIController.sharedInstance().sendChatMessage(self.summaryTextView.text, toRoom: room.token, threadTitle: nil, replyTo: -1, referenceId: nil, silently: false, for: activeAccount) { error in
                    if error == nil {
                        NotificationPresenter.shared().present(text: NSLocalizedString("Added note to self", comment: ""), dismissAfterDelay: 5.0, includedStyle: .success)
                    } else {
                        self.saveToNoteToSelf.setButtonEnabled(enabled: true)
                        NotificationPresenter.shared().present(text: NSLocalizedString("An error occurred while adding note", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
                    }
                }
            } else {
                self.saveToNoteToSelf.setButtonEnabled(enabled: true)
                NotificationPresenter.shared().present(text: NSLocalizedString("An error occurred while adding note", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
            }
        }
    }
}
