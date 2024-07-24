//
// SPDX-FileCopyrightText: 2021 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objcMembers public class DateLabelCustom: UILabel {

    weak var tableView: UITableView?

    func labelTapped(recognizer: UIGestureRecognizer) {
        let locationOfTouch = recognizer.location(in: self.tableView)
        if let location = self.tableView!.indexPathForRow(at: locationOfTouch) {
            DispatchQueue.main.async {
                self.tableView?.scrollToRow(at: IndexPath(row: 0, section: location.section), at: .none, animated: true)
                self.tableView?.layoutSubviews()
            }
        }
    }

   required init?(coder: NSCoder) {
        super.init(coder: coder)
        let gesture = UITapGestureRecognizer(target: self, action: #selector(labelTapped))
        self.addGestureRecognizer(gesture)
        self.isUserInteractionEnabled = true
    }

}
