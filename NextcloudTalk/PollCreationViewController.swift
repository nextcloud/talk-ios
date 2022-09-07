//
// Copyright (c) 2022 Ivan Sein <ivan@nextcloud.com>
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

@objc protocol PollCreationViewControllerDelegate {
    func wantsToCreatePoll(question: String, options: [String], resultMode: NCPollResultMode, maxVotes: Int)
}

@objcMembers class PollCreationViewController: UITableViewController, UITextFieldDelegate {

    enum PollCreationSection: Int {
        case kPollCreationSectionQuestion = 0
        case kPollCreationSectionOptions
        case kPollCreationSectionSettings
        case kPollCreationSectionCount
    }

    enum PollSetting: Int {
        case kPollSettingPrivate = 0
        case kPollSettingMultiple
        case kPollSettingCount
    }

    let kQuestionTextFieldTag = 9999

    public weak var pollCreationDelegate: PollCreationViewControllerDelegate?
    var question: String = ""
    var options: [String] = ["", ""]
    var privateSwitch = UISwitch()
    var multipleSwitch = UISwitch()
    let footerView = PollFooterView(frame: CGRect.zero)

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.initPollCreationView()
    }

    required override init(style: UITableView.Style) {
        super.init(style: style)
        self.initPollCreationView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false
        self.navigationItem.title = NSLocalizedString("New poll", comment: "")

        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
            appearance.backgroundColor = NCAppBranding.themeColor()
            self.navigationItem.standardAppearance = appearance
            self.navigationItem.compactAppearance = appearance
            self.navigationItem.scrollEdgeAppearance = appearance
        }

        // Set footer buttons
        self.tableView.tableFooterView = pollFooterView()

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
        self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
    }

    func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    func pollFooterView() -> UIView {
        footerView.primaryButton.setTitle(NSLocalizedString("Create poll", comment: ""), for: .normal)
        footerView.setPrimaryButtonAction(target: self, selector: #selector(createPollButtonPressed))
        footerView.frame = CGRect(x: 0, y: 0, width: 0, height: PollFooterView.heightForOption)
        footerView.secondaryButton.isHidden = true
        checkIfPollIsReadyToCreate()
        return footerView
    }

    func createPollButtonPressed() {
        let resultMode: NCPollResultMode = privateSwitch.isOn ? NCPollResultModeHidden : NCPollResultModePublic
        let maxVotes: Int = multipleSwitch.isOn ? 0 : 1
        self.pollCreationDelegate?.wantsToCreatePoll(question: question, options: options, resultMode: resultMode, maxVotes: maxVotes)
    }

    func checkIfPollIsReadyToCreate() {
        footerView.primaryButton.isEnabled = false
        if !question.isEmpty && !options[0].isEmpty && !options[1].isEmpty {
            footerView.primaryButton.isEnabled = true
        }
    }

    func initPollCreationView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.keyboardDismissMode = UIScrollView.KeyboardDismissMode.onDrag
        self.tableView.register(UINib(nibName: kTextInputTableViewCellNibName, bundle: nil), forCellReuseIdentifier: kTextInputCellIdentifier)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return PollCreationSection.kPollCreationSectionCount.rawValue
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == PollCreationSection.kPollCreationSectionQuestion.rawValue {
            return 1
        } else if section == PollCreationSection.kPollCreationSectionOptions.rawValue {
            return options.count + 1
        } else if section == PollCreationSection.kPollCreationSectionSettings.rawValue {
            return PollSetting.kPollSettingCount.rawValue
        }
        return 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == PollCreationSection.kPollCreationSectionQuestion.rawValue {
            return NSLocalizedString("Question", comment: "")
        } else if section == PollCreationSection.kPollCreationSectionOptions.rawValue {
            return NSLocalizedString("Poll options", comment: "")
        } else if section == PollCreationSection.kPollCreationSectionSettings.rawValue {
            return NSLocalizedString("Settings", comment: "")
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let textInputCell = tableView.dequeueReusableCell(withIdentifier: kTextInputCellIdentifier) as? TextInputTableViewCell ??
        TextInputTableViewCell(style: .default, reuseIdentifier: kTextInputCellIdentifier)
        textInputCell.textField.delegate = self
        let actionCell = tableView.dequeueReusableCell(withIdentifier: "PollSettingCellIdentifier") ?? UITableViewCell(style: .default, reuseIdentifier: "PollSettingCellIdentifier")

        if indexPath.section == PollCreationSection.kPollCreationSectionQuestion.rawValue {
            textInputCell.textField.placeholder = NSLocalizedString("Ask a question", comment: "")
            textInputCell.textField.tag = kQuestionTextFieldTag
            return textInputCell
        } else if indexPath.section == PollCreationSection.kPollCreationSectionOptions.rawValue {
            textInputCell.textField.placeholder = NSLocalizedString("Option", comment: "")
            textInputCell.textField.tag = indexPath.row
            if indexPath.row == options.count {
                actionCell.textLabel?.text = NSLocalizedString("Add option", comment: "")
                actionCell.imageView?.image = UIImage(named: "add")?.withRenderingMode(.alwaysTemplate)
                actionCell.imageView?.tintColor = UIColor(red: 0.43, green: 0.43, blue: 0.45, alpha: 1)
                return actionCell
            }
            return textInputCell
        } else if indexPath.section == PollCreationSection.kPollCreationSectionSettings.rawValue {
            if indexPath.row == PollSetting.kPollSettingPrivate.rawValue {
                actionCell.textLabel?.text = NSLocalizedString("Private poll", comment: "")
                actionCell.accessoryView = privateSwitch
                return actionCell
            } else if indexPath.row == PollSetting.kPollSettingMultiple.rawValue {
                actionCell.textLabel?.text = NSLocalizedString("Multiple answers", comment: "")
                actionCell.accessoryView = multipleSwitch
                return actionCell
            }
            return actionCell
        }

        return actionCell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - UITextField delegate

    func textFieldDidEndEditing(_ textField: UITextField) {
        let value = textField.text!.trimmingCharacters(in: CharacterSet.whitespaces)
        textField.text = value
        setValueFromTextField(textField: textField, value: value)
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let value = (textField.text as NSString?)?.replacingCharacters(in: range, with: string).trimmingCharacters(in: CharacterSet.whitespaces)
        setValueFromTextField(textField: textField, value: value ?? "")
        return true
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        setValueFromTextField(textField: textField, value: "")
        return true
    }

    func setValueFromTextField(textField: UITextField, value: String) {
        if textField.tag == kQuestionTextFieldTag {
            question = value
        } else {
            options[textField.tag] = value
        }
        checkIfPollIsReadyToCreate()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
