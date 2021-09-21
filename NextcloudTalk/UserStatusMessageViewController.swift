/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import UIKit

import NCCommunication

class UserStatusMessageViewController: UIViewController {

    @IBOutlet weak var statusEmojiLabel: UILabel!
    @IBOutlet weak var statusMessageTextField: UITextField!
    @IBOutlet weak var statusTableView: UITableView!
    @IBOutlet weak var clearStatusLabel: UILabel!
    @IBOutlet weak var clearAtLabel: UILabel!
    @IBOutlet weak var clearStatusButton: UIButton!
    @IBOutlet weak var setStatusButton: UIButton!
    
    public var userStatus: NCUserStatus?
    private var statusPredefinedStatuses: [NCCommunicationUserStatus] = []
    
    @objc init(userStatus:NCUserStatus) {
        self.userStatus = userStatus;
        super.init(nibName: "UserStatusMessageViewController", bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor:NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("Status message", comment: "")
        
        self.navigationController?.navigationBar.topItem?.leftBarButtonItem = UIBarButtonItem.init(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))

        statusTableView.delegate = self
        statusTableView.register(UITableViewCell.self, forCellReuseIdentifier: "PredefinedStatusCellIdentifier")
        statusTableView.contentInset = UIEdgeInsets.init(top: 0, left: -10, bottom: 0, right: 0)
        statusEmojiLabel.layer.cornerRadius = 4.0
        statusEmojiLabel.layer.masksToBounds = true
        statusMessageTextField.placeholder = NSLocalizedString("What's your status?", comment: "")
        clearStatusLabel.text = NSLocalizedString("Clear status message after", comment: "")
        clearAtLabel.text = NSLocalizedString("Don't clear", comment: "")
        clearAtLabel.layer.cornerRadius = 4.0
        clearAtLabel.layer.masksToBounds = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.clearAtLabelPressed))
        clearAtLabel.isUserInteractionEnabled = true
        clearAtLabel.addGestureRecognizer(tap)
        clearStatusButton.setTitle(NSLocalizedString("Clear status message", comment: ""), for: .normal)
        clearStatusButton.layer.cornerRadius = 20.0
        clearStatusButton.layer.masksToBounds = true
        setStatusButton.setTitle(NSLocalizedString("Set status message", comment: ""), for: .normal)
        setStatusButton.backgroundColor = NCAppBranding.themeColor()
        setStatusButton.setTitleColor(NCAppBranding.themeTextColor(), for: .normal)
        setStatusButton.setTitleColor(NCAppBranding.themeTextColor().withAlphaComponent(0.5), for: .disabled)
        setStatusButton.layer.cornerRadius = 20.0
        setStatusButton.layer.masksToBounds = true
        
        self.getStatus()
    }
    
    @IBAction func clearStatusButtonPressed(_ sender: Any) {
        NCCommunication.shared.clearMessage { account, errorCode, errorDescription in
            self.dismiss(animated: true)
        }
    }
    
    @objc func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc func clearAtLabelPressed() {
        let alert = UIAlertController(title: NSLocalizedString("Clear status message after", comment: ""), message: nil, preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Don't clear", comment: ""), style: .default, handler: nil))
        alert.addAction(UIAlertAction(title: NSLocalizedString("30 minutes", comment: ""), style: .default, handler: nil))
        alert.addAction(UIAlertAction(title: NSLocalizedString("1 hour", comment: ""), style: .default, handler: nil))
        alert.addAction(UIAlertAction(title: NSLocalizedString("4 hours", comment: ""), style: .default, handler: nil))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Today", comment: ""), style: .default, handler: nil))
        alert.addAction(UIAlertAction(title: NSLocalizedString("This week", comment: ""), style: .default, handler: nil))
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))

        self.present(alert, animated: true)
    }
    
    func getStatus() {
        NCAPIController.sharedInstance().setupNCCommunication(for: NCDatabaseManager.sharedInstance().activeAccount())
        NCCommunication.shared.getUserStatus { account, clearAt, icon, message, messageId, messageIsPredefined, status, statusIsUserDefined, userId, errorCode, errorDescription in
            if icon != nil {
                self.statusEmojiLabel.text = icon
            }
            
            if message != nil {
                self.statusMessageTextField.text = message
            }
            
            if clearAt != nil {
                self.clearAtLabel.text = self.getPredefinedClearStatusText(clearAt: clearAt, clearAtTime: nil, clearAtType: nil)
            }
            
            NCCommunication.shared.getUserStatusPredefinedStatuses { account, userStatuses, errorCode, errorDescription in
                
                if errorCode == 0 {

                    if let userStatuses = userStatuses {
                        self.statusPredefinedStatuses = userStatuses
                    }

                    self.statusTableView.reloadData()
                }
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
            case "3600":
                return NSLocalizedString("an hour", comment: "")
            case "1800":
                return NSLocalizedString("30 minutes", comment: "")
            default:
                return NSLocalizedString("Don't clear", comment: "")
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
                return NSLocalizedString(clearAtTime!, comment: "")
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
        
        cell.setSelected(false, animated: true)

        if let messageId = status.id {
            
            let clearAtTimestampString = self.getPredefinedClearStatusText(clearAt: status.clearAt, clearAtTime: status.clearAtTime, clearAtType: status.clearAtType)
            let cleatAt = self.getClearAt(clearAtTimestampString)
            
            NCCommunication.shared.setCustomMessagePredefined(messageId: messageId, clearAt:cleatAt) { account, errorCode, errorDescription in

                if errorCode == 0 {
                    self.statusEmojiLabel.text = status.icon
                    self.statusMessageTextField.text = status.message
                    self.clearAtLabel.text = clearAtTimestampString
                }
            }
        }
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
