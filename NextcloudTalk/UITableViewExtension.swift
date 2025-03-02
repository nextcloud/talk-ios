//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

extension UITableView {

    func dequeueOrCreateCell<T: UITableViewCell>(withIdentifier identifier: String, style: UITableViewCell.CellStyle = .default) -> T {
        if let cell = self.dequeueReusableCell(withIdentifier: identifier) as? T {
            return cell
        }

        return T(style: style, reuseIdentifier: identifier)
    }

    func isValid(indexPath: IndexPath) -> Bool {
        indexPath.row >= 0 && indexPath.section >= 0 &&
        indexPath.section < self.numberOfSections &&
        indexPath.row < self.numberOfRows(inSection: indexPath.section)
    }
}
