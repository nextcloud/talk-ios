//
// Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
//
// Author Ivan Sein <ivan@nextcloud.com>
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

import NextcloudKit

@objc protocol UserStatusMessageViewControllerDelegate {
    func didClearStatusMessage()
    func didSetStatusMessage(icon: String?, message: String?, clearAt: NSDate?)
}

class UserStatusMessageViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var statusEmojiTextField: EmojiTextField!
    @IBOutlet weak var statusMessageTextField: UITextField!
    @IBOutlet weak var statusTableView: UITableView!
    @IBOutlet weak var clearStatusLabel: UILabel!
    @IBOutlet weak var clearAtLabel: UILabel!
    @IBOutlet weak var clearStatusButton: NCButton!
    @IBOutlet weak var setStatusButton: NCButton!

    public var userStatus: NCUserStatus?
    @objc public weak var delegate: UserStatusMessageViewControllerDelegate?

    private var predefinedStatusSelected: NKUserStatus?
    private var iconSelected: String?
    private var clearAtSelected: Double = 0
    private var statusPredefinedStatuses: [NKUserStatus] = []

    @objc init(userStatus: NCUserStatus) {
        self.userStatus = userStatus
        super.init(nibName: "UserStatusMessageViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Status message", comment: "")

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        appearance.backgroundColor = NCAppBranding.themeColor()
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

        self.navigationController?.navigationBar.topItem?.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))

        statusTableView.delegate = self
        statusTableView.register(UITableViewCell.self, forCellReuseIdentifier: "PredefinedStatusCellIdentifier")
        statusTableView.contentInset = UIEdgeInsets(top: 0, left: -10, bottom: 0, right: 0)

        statusEmojiTextField.delegate = self

        statusMessageTextField.placeholder = NSLocalizedString("What is your status?", comment: "")
        statusMessageTextField.returnKeyType = .done
        statusMessageTextField.delegate = self

        clearStatusLabel.text = NSLocalizedString("Clear status message after", comment: "")

        clearAtLabel.text = NSLocalizedString("Don't clear", comment: "")
        clearAtLabel.layer.cornerRadius = 4.0
        clearAtLabel.layer.masksToBounds = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.clearAtLabelPressed))
        clearAtLabel.isUserInteractionEnabled = true
        clearAtLabel.addGestureRecognizer(tap)

        clearStatusButton.setTitle(NSLocalizedString("Clear status message", comment: ""), for: .normal)
        clearStatusButton.setButtonStyle(style: .tertiary)

        setStatusButton.setTitle(NSLocalizedString("Set status message", comment: ""), for: .normal)
        setStatusButton.setButtonStyle(style: .primary)

        let clearAtDate = NSDate(timeIntervalSince1970: Double(self.userStatus?.clearAt ?? 0))
        self.setCustomStatusInView(icon: self.userStatus?.icon, message: self.userStatus?.message, clearAt: clearAtDate)

        self.getStatus()
    }

    @IBAction func clearStatusButtonPressed(_ sender: Any) {
        NextcloudKit.shared.clearMessage { _, error in
            if error.errorCode == 0 {
                self.delegate?.didClearStatusMessage()
                self.dismiss(animated: true)
            } else {
                self.showErrorDialog(title: NSLocalizedString("Could not clear status message", comment: ""),
                                     message: NSLocalizedString("An error occurred while clearing status message", comment: ""))
            }
        }
    }

    @IBAction func setStatusButtonPressed(_ sender: Any) {
        guard let message = statusMessageTextField.text else { return }

        if predefinedStatusSelected != nil && predefinedStatusSelected?.message == message && predefinedStatusSelected?.icon == statusEmojiTextField.text {
            NextcloudKit.shared.setCustomMessagePredefined(messageId: predefinedStatusSelected!.id!, clearAt: clearAtSelected) { _, error in
                if error.errorCode == 0 {
                    let clearAtDate = NSDate(timeIntervalSince1970: self.clearAtSelected)
                    self.delegate?.didSetStatusMessage(icon: self.predefinedStatusSelected?.icon, message: self.predefinedStatusSelected?.message, clearAt: clearAtDate)
                    self.dismiss(animated: true)
                } else {
                    self.showErrorDialog(title: NSLocalizedString("Could not set status message", comment: ""),
                                         message: NSLocalizedString("An error occurred while setting status message", comment: ""))
                }
            }
        } else {
            NextcloudKit.shared.setCustomMessageUserDefined(statusIcon: iconSelected, message: message, clearAt: clearAtSelected) { _, error in
                if error.errorCode == 0 {
                    let clearAtDate = NSDate(timeIntervalSince1970: self.clearAtSelected)
                    self.delegate?.didSetStatusMessage(icon: self.iconSelected, message: message, clearAt: clearAtDate)
                    self.dismiss(animated: true)
                } else {
                    self.showErrorDialog(title: NSLocalizedString("Could not set status message", comment: ""),
                                         message: NSLocalizedString("An error occurred while setting status message", comment: ""))
                }
            }
        }
    }

    @objc func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    @objc func clearAtLabelPressed() {
        let alert = UIAlertController(title: NSLocalizedString("Clear status message after", comment: ""), message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: NSLocalizedString("Don't clear", comment: ""), style: .default,
                                      handler: {(_: UIAlertAction!) in self.setClearAt(clearAt: NSLocalizedString("Don't clear", comment: ""))}))
        alert.addAction(UIAlertAction(title: NSLocalizedString("30 minutes", comment: ""), style: .default,
                                      handler: {(_: UIAlertAction!) in self.setClearAt(clearAt: NSLocalizedString("30 minutes", comment: ""))}))
        alert.addAction(UIAlertAction(title: NSLocalizedString("1 hour", comment: ""), style: .default,
                                      handler: {(_: UIAlertAction!) in self.setClearAt(clearAt: NSLocalizedString("1 hour", comment: ""))}))
        alert.addAction(UIAlertAction(title: NSLocalizedString("4 hours", comment: ""), style: .default,
                                      handler: {(_: UIAlertAction!) in self.setClearAt(clearAt: NSLocalizedString("4 hours", comment: ""))}))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Today", comment: ""), style: .default,
                                      handler: {(_: UIAlertAction!) in self.setClearAt(clearAt: NSLocalizedString("Today", comment: ""))}))
        alert.addAction(UIAlertAction(title: NSLocalizedString("This week", comment: ""), style: .default,
                                      handler: {(_: UIAlertAction!) in self.setClearAt(clearAt: NSLocalizedString("This week", comment: ""))}))

        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))

        // Presentation on iPads
        alert.popoverPresentationController?.sourceView = clearAtLabel

        self.present(alert, animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        statusMessageTextField.resignFirstResponder()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        self.checkSetUserStatusButtonState()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField is EmojiTextField {
            if string.isSingleEmoji == false {
                self.setStatusIconInView(icon: nil)
            } else {
                self.setStatusIconInView(icon: string)
            }

            textField.endEditing(true)

            return false
        }

        return true
    }

    func checkSetUserStatusButtonState() {
        if statusMessageTextField.text!.isEmpty == true {
            setStatusButton.setButtonEnabled(enabled: false)
        } else {
            setStatusButton.setButtonEnabled(enabled: true)
        }
    }

    func setClearAt(clearAt: String) {
        self.clearAtSelected = self.getClearAt(clearAt)
        self.clearAtLabel.text = clearAt
    }

    func setCustomStatusInView(icon: String?, message: String?, clearAt: NSDate?) {
        clearAtSelected = clearAt?.timeIntervalSince1970 ?? 0
        let clearAtString = self.getPredefinedClearStatusText(clearAt: clearAt, clearAtTime: nil, clearAtType: nil)
        self.setStatusInView(icon: icon, message: message, clearAt: clearAtString)
    }

    func setPredefinedStatusInView(predefinedStatus: NKUserStatus?) {
        predefinedStatusSelected = predefinedStatus
        let clearAtString = self.getPredefinedClearStatusText(clearAt: predefinedStatus?.clearAt, clearAtTime: predefinedStatus?.clearAtTime, clearAtType: predefinedStatus?.clearAtType)
        clearAtSelected = self.getClearAt(clearAtString)
        self.setStatusInView(icon: predefinedStatus?.icon, message: predefinedStatus?.message, clearAt: clearAtString)
    }

    func setStatusInView(icon: String?, message: String?, clearAt: String?) {
        self.setStatusIconInView(icon: icon)
        self.statusMessageTextField.text = message
        self.clearAtLabel.text = clearAt
        self.checkSetUserStatusButtonState()
    }

    func setStatusIconInView(icon: String?) {
        if icon == nil || icon?.isEmpty == true {
            iconSelected = nil
            statusEmojiTextField.text = "😀"
            statusEmojiTextField.alpha = 0.5
        } else {
            iconSelected = icon
            statusEmojiTextField.text = icon
            statusEmojiTextField.alpha = 1
        }
    }

    func showErrorDialog(title: String?, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }

    func getStatus() {
        NCAPIController.sharedInstance().setupNCCommunication(for: NCDatabaseManager.sharedInstance().activeAccount())
        NextcloudKit.shared.getUserStatus { _, clearAt, icon, message, _, _, _, _, _, _, error in
            if error.errorCode == 0 {
                self.setCustomStatusInView(icon: icon, message: message, clearAt: clearAt)
            }
        }
        NextcloudKit.shared.getUserStatusPredefinedStatuses { _, userStatuses, _, error in
            if error.errorCode == 0 {
                self.statusPredefinedStatuses = userStatuses!
                self.statusTableView.reloadData()
            }
        }
    }

    func getClearAt(_ clearAtString: String) -> Double {
        let now = Date()
        let calendar = Calendar.current
        let gregorian = Calendar(identifier: .gregorian)
        let midnight = calendar.startOfDay(for: now)

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: midnight) else { return 0 }
        guard let startweek = gregorian.date(from: gregorian.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return 0 }
        guard let endweek = gregorian.date(byAdding: .day, value: 6, to: startweek) else { return 0 }

        switch clearAtString {
        case NSLocalizedString("Don't clear", comment: ""):
            return 0
        case NSLocalizedString("30 minutes", comment: ""):
            let date = now.addingTimeInterval(1800)
            return date.timeIntervalSince1970
        case NSLocalizedString("1 hour", comment: ""), NSLocalizedString("an hour", comment: ""):
            let date = now.addingTimeInterval(3600)
            return date.timeIntervalSince1970
        case NSLocalizedString("4 hours", comment: ""):
            let date = now.addingTimeInterval(14400)
            return date.timeIntervalSince1970
        case NSLocalizedString("Today", comment: ""):
            return tomorrow.timeIntervalSince1970
        case NSLocalizedString("This week", comment: ""):
            return endweek.timeIntervalSince1970
        default:
            return 0
        }
    }

    func getPredefinedClearStatusText(clearAt: NSDate?, clearAtTime: String?, clearAtType: String?) -> String {
        // Date
        if clearAt != nil {
            let from = Date()
            let to = clearAt! as Date

            let day = Calendar.current.dateComponents([.day], from: from, to: to).day ?? 0
            let hour = Calendar.current.dateComponents([.hour], from: from, to: to).hour ?? 0
            let minute = Calendar.current.dateComponents([.minute], from: from, to: to).minute ?? 0

            if day > 0 {
                if day == 1 { return NSLocalizedString("Today", comment: "") }
                return "\(day) " + NSLocalizedString("days", comment: "")
            }

            if hour > 0 {
                if hour == 1 { return NSLocalizedString("an hour", comment: "") }
                if hour == 4 { return NSLocalizedString("4 hours", comment: "") }
                return "\(hour) " + NSLocalizedString("hours", comment: "")
            }

            if minute > 0 {
                if minute >= 25 && minute <= 30 { return NSLocalizedString("30 minutes", comment: "") }
                if minute > 30 { return NSLocalizedString("an hour", comment: "") }
                return "\(minute) " + NSLocalizedString("minutes", comment: "")
            }
        }

        // Period
        if clearAtTime != nil && clearAtType == "period" {
            switch clearAtTime {
            case "14400":
                return NSLocalizedString("4 hours", comment: "")
            case "3600":
                return NSLocalizedString("an hour", comment: "")
            case "1800":
                return NSLocalizedString("30 minutes", comment: "")
            default:
                return clearAtTime!
            }
        }

        // End of
        if clearAtTime != nil && clearAtType == "end-of" {
            switch clearAtTime {
            case "day":
                return NSLocalizedString("Today", comment: "")
            case "week":
                return NSLocalizedString("This week", comment: "")
            default:
                return clearAtTime!
            }
        }

        return NSLocalizedString("Don't clear", comment: "")
    }

}

extension UserStatusMessageViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 45
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) else { return }
        let status = statusPredefinedStatuses[indexPath.row]

        self.setPredefinedStatusInView(predefinedStatus: status)

        cell.setSelected(false, animated: true)
    }
}

extension UserStatusMessageViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return statusPredefinedStatuses.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PredefinedStatusCellIdentifier", for: indexPath)
        let status = statusPredefinedStatuses[indexPath.row]
        var timeString = getPredefinedClearStatusText(clearAt: status.clearAt, clearAtTime: status.clearAtTime, clearAtType: status.clearAtType)

        if let messageText = status.message {
            let statusString = status.icon! + "    " + messageText
            timeString = " - " + timeString
            let attributedString: NSMutableAttributedString = NSMutableAttributedString(string: statusString + timeString)
            attributedString.setColor(color: UIColor.lightGray, font: UIFont.systemFont(ofSize: 15), forText: timeString)
            cell.textLabel?.attributedText = attributedString
        }

        return cell
    }
}
