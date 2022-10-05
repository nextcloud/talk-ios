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

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        appearance.backgroundColor = NCAppBranding.themeColor()
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

        self.tableView.isEditing = true

        // Set footer buttons
        self.tableView.tableFooterView = pollFooterView()

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
        self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
    }

    override func viewDidAppear(_ animated: Bool) {
        if let questionCell = self.tableView.cellForRow(at: IndexPath(row: 0, section: PollCreationSection.kPollCreationSectionQuestion.rawValue)) as? TextInputTableViewCell {
            questionCell.textField.becomeFirstResponder()
        }
    }

    func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    func pollFooterView() -> UIView {
        footerView.primaryButton.setTitle(NSLocalizedString("Create poll", comment: ""), for: .normal)
        footerView.primaryButton.setButtonAction(target: self, selector: #selector(createPollButtonPressed))
        footerView.frame = CGRect(x: 0, y: 0, width: 0, height: PollFooterView.heightForOption)
        footerView.secondaryButtonContainerView.isHidden = true
        checkIfPollIsReadyToCreate()
        return footerView
    }

    func createPollButtonPressed() {
        let resultMode: NCPollResultMode = privateSwitch.isOn ? NCPollResultModeHidden : NCPollResultModePublic
        let maxVotes: Int = multipleSwitch.isOn ? 0 : 1
        self.pollCreationDelegate?.wantsToCreatePoll(question: question, options: options, resultMode: resultMode, maxVotes: maxVotes)
    }

    func checkIfPollIsReadyToCreate() {
        footerView.primaryButton.setButtonEnabled(enabled: false)
        if !question.isEmpty && options.filter({!$0.isEmpty}).count >= 2 {
            footerView.primaryButton.setButtonEnabled(enabled: true)
        }
    }

    func initPollCreationView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.keyboardDismissMode = UIScrollView.KeyboardDismissMode.onDrag
        self.tableView.register(UINib(nibName: kTextInputTableViewCellNibName, bundle: nil), forCellReuseIdentifier: kTextInputCellIdentifier)
    }

    // MARK: - Table view data source

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if indexPath.section == PollCreationSection.kPollCreationSectionOptions.rawValue {
            return true
        }
        return false
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if indexPath.section == PollCreationSection.kPollCreationSectionOptions.rawValue {
            if indexPath.row == options.count {
                return .insert
            }
            if indexPath.row > 1 || options.count > 2 {
                return .delete
            }
        }
        return .none
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if indexPath.section == PollCreationSection.kPollCreationSectionOptions.rawValue {
            if indexPath.row == options.count {
                options.insert("", at: indexPath.row)
                tableView.beginUpdates()
                tableView.insertRows(at: [indexPath], with: .automatic)
                tableView.endUpdates()
                if let optionCell = self.tableView.cellForRow(at: indexPath) as? TextInputTableViewCell {
                    optionCell.textField.becomeFirstResponder()
                }
            } else {
                options.remove(at: indexPath.row)
                self.tableView.reloadSections([PollCreationSection.kPollCreationSectionOptions.rawValue], with: .automatic)
            }
            checkIfPollIsReadyToCreate()
        }
    }

    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return false
    }

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
            return NSLocalizedString("Answers", comment: "")
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
            textInputCell.textField.text = question
            return textInputCell
        } else if indexPath.section == PollCreationSection.kPollCreationSectionOptions.rawValue {
            if indexPath.row == options.count {
                actionCell.textLabel?.text = NSLocalizedString("Add answer", comment: "")
                return actionCell
            } else if indexPath.row < options.count {
                textInputCell.textField.placeholder = NSLocalizedString("Answer", comment: "") + " " + String(indexPath.row + 1)
                textInputCell.textField.tag = indexPath.row
                textInputCell.textField.text = options[indexPath.row]
                return textInputCell
            }
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
        } else if textField.tag < options.count {
            options[textField.tag] = value
        }
        checkIfPollIsReadyToCreate()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
