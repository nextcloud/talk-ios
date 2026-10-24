//
// SPDX-FileCopyrightText: 2021 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class DetailedOption: NSObject {
    var identifier = ""
    var title = ""
    var subtitle = ""
    var image: UIImage?
    var selected = false
}

protocol DetailedOptionsSelectorTableViewControllerDelegate: AnyObject {
    func detailedOptionsSelector(_ viewController: DetailedOptionsSelectorTableViewController, didSelectOptionWithIdentifier option: DetailedOption)
    func detailedOptionsSelectorWasCancelled(_ viewController: DetailedOptionsSelectorTableViewController)
}

class DetailedOptionsSelectorTableViewController: UITableViewController {

    enum SelectorType {
        case `default`
        case accounts
    }

    weak var delegate: DetailedOptionsSelectorTableViewControllerDelegate?
    var options: [DetailedOption]
    var senderId = ""
    private let type: SelectorType

    init(options: [DetailedOption], forSenderIdentifier senderId: String, andStyle style: UITableView.Style) {
        self.options = options
        self.senderId = senderId
        self.type = .default
        super.init(style: style)
    }

    init(accounts: [DetailedOption], andStyle style: UITableView.Style) {
        self.options = accounts
        self.type = .accounts
        super.init(style: style)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonPressed))
        self.navigationController?.navigationBar.topItem?.leftBarButtonItem = cancelButton
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return options.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let option = options[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "DetailOptionIdentifier")

        if type == .accounts {
            cell.imageView?.image = NCUtils.renderAspectImage(image: option.image, ofSize: CGSize(width: 20, height: 20), centerImage: true)
            cell.detailTextLabel?.text = option.subtitle.replacingOccurrences(of: "https://", with: "", options: .caseInsensitive)
            cell.detailTextLabel?.textColor = .secondaryLabel
        } else {
            cell.imageView?.image = option.image
            cell.detailTextLabel?.text = option.subtitle
        }

        cell.textLabel?.text = option.title
        cell.detailTextLabel?.numberOfLines = 0
        cell.detailTextLabel?.sizeToFit()
        cell.accessoryType = option.selected ? .checkmark : .none

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        delegate?.detailedOptionsSelector(self, didSelectOptionWithIdentifier: options[indexPath.row])
    }

    @objc func cancelButtonPressed() {
        delegate?.detailedOptionsSelectorWasCancelled(self)
    }
}
