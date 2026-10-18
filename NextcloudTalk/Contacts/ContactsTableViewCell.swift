//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

let kContactCellIdentifier = "ContactCellIdentifier"
let kContactsTableCellNibName = "ContactsTableViewCell"
let kContactsTableCellHeight: CGFloat = 72.0
let kContactsTableCellTitleFontSize: CGFloat = 17.0

// The xib references the class without a module
@objc(ContactsTableViewCell)
class ContactsTableViewCell: UITableViewCell {

    @IBOutlet weak var avatarView: AvatarView!
    @IBOutlet weak var labelTitle: UILabel!
    @IBOutlet weak var userStatusMessageLabel: UILabel!
    @IBOutlet private weak var titleStackView: UIStackView!

    let roleIconView = UIImageView()

    private let roleIconSize: CGFloat = 15.0
    private let roleIconSpacing: CGFloat = 4.0
    private var roleIconLeadingConstraint: NSLayoutConstraint?
    private var roleIconWidthConstraint: NSLayoutConstraint?

    override func awakeFromNib() {
        super.awakeFromNib()
        setupRoleIconView()
    }

    private func setupRoleIconView() {
        roleIconView.translatesAutoresizingMaskIntoConstraints = false
        roleIconView.contentMode = .scaleAspectFit
        roleIconView.tintColor = .secondaryLabel
        roleIconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentView.addSubview(roleIconView)

        // The labels are leading-aligned in their stack view and hug their text, so the
        // icon can follow the name directly instead of sitting at the edge of the cell
        let leadingConstraint = roleIconView.leadingAnchor.constraint(equalTo: labelTitle.trailingAnchor)
        let widthConstraint = roleIconView.widthAnchor.constraint(equalToConstant: 0)
        roleIconLeadingConstraint = leadingConstraint
        roleIconWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            leadingConstraint,
            widthConstraint,
            roleIconView.centerYAnchor.constraint(equalTo: labelTitle.centerYAnchor),
            // Truncate the name rather than the icon
            roleIconView.trailingAnchor.constraint(lessThanOrEqualTo: titleStackView.trailingAnchor),
            labelTitle.trailingAnchor.constraint(lessThanOrEqualTo: titleStackView.trailingAnchor),
            userStatusMessageLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleStackView.trailingAnchor)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        // Fix problem of rendering downloaded image in a reused cell
        avatarView.prepareForReuse()

        userStatusMessageLabel.text = ""
        userStatusMessageLabel.isHidden = true
        labelTitle.text = ""
        labelTitle.textColor = .label
        labelTitle.font = .systemFont(ofSize: kContactsTableCellTitleFontSize, weight: .regular)
        setRoleIcon(nil, withAccessibilityLabel: nil)
    }

    func setRoleIcon(_ systemImageName: String?, withAccessibilityLabel accessibilityLabel: String?) {
        let configuration = UIImage.SymbolConfiguration(pointSize: roleIconSize)
        let icon = systemImageName.flatMap { UIImage(systemName: $0, withConfiguration: configuration) }

        roleIconView.image = icon
        roleIconView.accessibilityLabel = accessibilityLabel

        // Without an icon the view collapses so it takes no space after the name
        roleIconLeadingConstraint?.constant = icon != nil ? roleIconSpacing : 0
        roleIconWidthConstraint?.constant = icon?.size.width ?? 0
    }

    func setUserStatusMessage(_ userStatusMessage: String?, withIcon userStatusIcon: String?) {
        guard let userStatusMessage, !userStatusMessage.isEmpty else {
            userStatusMessageLabel.isHidden = true
            return
        }

        if let userStatusIcon, !userStatusIcon.isEmpty {
            userStatusMessageLabel.text = "\(userStatusIcon) \(userStatusMessage)"
        } else {
            userStatusMessageLabel.text = userStatusMessage
        }

        userStatusMessageLabel.isHidden = false
    }
}
