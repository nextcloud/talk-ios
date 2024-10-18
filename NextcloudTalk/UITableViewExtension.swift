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
}
