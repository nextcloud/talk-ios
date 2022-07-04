//
// Copyright (c) 2021 Aleksandra Lazarevic <aleksandra@nextcloud.com>
//
// Author Aleksandra Lazarevic <aleksandra@nextcloud.com>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
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
