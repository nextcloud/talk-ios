//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import Foundation
import SwiftyAttributes

@objcMembers class MessageTextViewController: UIViewController {

    @IBOutlet public weak var messageTextView: UITextView!

    private var messageText = ""

    init(messageText: String) {
        super.init(nibName: "MessageTextViewController", bundle: nil)

        self.messageText = messageText
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Close", comment: ""), primaryAction: UIAction { [unowned self] _ in
            self.dismiss(animated: true)
        })

        self.messageTextView.layer.cornerRadius = 8
        self.messageTextView.layer.masksToBounds = true
        self.messageTextView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        self.messageTextView.text = messageText
    }

}
