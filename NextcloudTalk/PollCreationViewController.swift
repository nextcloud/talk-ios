//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objcMembers class PollCreationViewController: UITableViewController, UITextFieldDelegate, PollDraftsViewControllerDelegate {

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

    var room: NCRoom
    var editingDraftId: Int?
    var draftsAvailable: Bool = false
    var question: String = ""
    var options: [String] = ["", ""]
    var anonymousPollSwitch = UISwitch()
    var multipleAnswersSwitch = UISwitch()
    var creatingPollIndicatorView = UIActivityIndicatorView()
    let footerView = PollFooterView(frame: CGRect.zero)

    required init?(coder aDecoder: NSCoder) {
        self.room = NCRoom()

        super.init(coder: aDecoder)
        self.initPollCreationView()
    }

    init(room: NCRoom) {
        self.room = room
        self.draftsAvailable = room.canModerate && NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityTalkPollsDrafts, forAccountId: room.accountId)

        super.init(style: .insetGrouped)
        self.initPollCreationView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.creatingPollIndicatorView = UIActivityIndicatorView()
        self.creatingPollIndicatorView.color = NCAppBranding.themeTextColor()

        self.setMoreOptionsButton()

        NCAppBranding.styleViewController(self)

        self.setNavigationBarTitle()
        self.tableView.isEditing = true

        // Configure footer buttons
        configureFooterButtons()

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))

        if #unavailable(iOS 26.0) {
            self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        if let questionCell = self.tableView.cellForRow(at: IndexPath(row: 0, section: PollCreationSection.kPollCreationSectionQuestion.rawValue)) as? TextFieldTableViewCell {
            questionCell.textField.becomeFirstResponder()
        }
    }

    func cancelButtonPressed() {
        close()
    }

    func close() {
        self.dismiss(animated: true, completion: nil)
    }

    func presentPollDraftsView() {
        let pollDraftsVC = PollDraftsViewController(room: room)
        pollDraftsVC.delegate = self
        let navController = UINavigationController(rootViewController: pollDraftsVC)
        present(navController, animated: true, completion: nil)
    }

    func didSelectPollDraft(draft: NCPoll, forEditing: Bool) {
        // End editing for any textfield
        self.view.endEditing(true)

        // Assign poll draft values
        self.question = draft.question
        self.options = draft.options.compactMap { $0 as? String }
        self.anonymousPollSwitch.isOn = draft.resultMode == .hidden
        self.multipleAnswersSwitch.isOn = draft.maxVotes == 0

        // Check if editing poll draft
        if forEditing {
            self.editingDraftId = draft.pollId
        } else {
            self.editingDraftId = nil
        }

        // Refresh poll creation view
        self.refreshPollCreationView()
    }

    func refreshPollCreationView() {
        self.tableView.reloadData()
        self.setNavigationBarTitle()
        self.setMoreOptionsButton()
        self.configureFooterButtons()
        self.checkIfPollIsReadyToCreate()
    }

    func setNavigationBarTitle() {
        if let editingDraftId = self.editingDraftId {
            self.navigationItem.title = NSLocalizedString("Editing poll draft", comment: "")
        } else {
            self.navigationItem.title = NSLocalizedString("New poll", comment: "")
        }
    }

    func showCreationError() {
        let alert = UIAlertController(title: NSLocalizedString("Creating poll failed", comment: ""),
                                      message: NSLocalizedString("An error occurred while creating the poll", comment: ""),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }

    func showEditionError() {
        let alert = UIAlertController(title: NSLocalizedString("Editing poll failed", comment: ""),
                                      message: NSLocalizedString("An error occurred while editing the poll", comment: ""),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }

    func showDraftCreationSuccess() {
        NotificationPresenter.shared().present(text: NSLocalizedString("Poll draft has been saved", comment: ""), dismissAfterDelay: 5.0, includedStyle: .dark)
    }

    func showPollCreationUI() {
        disablePollCreationButtons()
        creatingPollIndicatorView.startAnimating()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: creatingPollIndicatorView)
    }

    func removePollCreationUI() {
        enablePollCreationButtons()
        creatingPollIndicatorView.stopAnimating()
        setMoreOptionsButton()
    }

    func setMoreOptionsButton() {
        if draftsAvailable, editingDraftId == nil {
            let menuAction = UIAction(
                title: NSLocalizedString("Browse poll drafts", comment: ""),
                image: UIImage(systemName: "doc")) { _ in
                self.presentPollDraftsView()
            }
            let menu = UIMenu(children: [menuAction])
            let menuButton = UIBarButtonItem(
                image: UIImage(systemName: "ellipsis.circle"),
                menu: menu
            )

            navigationItem.rightBarButtonItem = menuButton
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    func enablePollCreationButtons() {
        footerView.primaryButton.setButtonEnabled(enabled: true)
        footerView.secondaryButton.setButtonEnabled(enabled: true)
    }

    func disablePollCreationButtons() {
        footerView.primaryButton.setButtonEnabled(enabled: false)
        footerView.secondaryButton.setButtonEnabled(enabled: false)
    }

    func configureFooterButtons() {
        if editingDraftId != nil {
            footerView.primaryButton.setTitle(NSLocalizedString("Save", comment: ""), for: .normal)
            footerView.primaryButton.setButtonAction(target: self, selector: #selector(saveEditedPollDraftButtonPressed))
        } else {
            footerView.primaryButton.setTitle(NSLocalizedString("Create poll", comment: ""), for: .normal)
            footerView.primaryButton.setButtonAction(target: self, selector: #selector(createPollButtonPressed))
        }

        footerView.frame = CGRect(x: 0, y: 0, width: 0, height: PollFooterView.heightForOption)
        footerView.secondaryButtonContainerView.isHidden = true

        if draftsAvailable, editingDraftId == nil {
            footerView.secondaryButton.setTitle(NSLocalizedString("Save as draft", comment: ""), for: .normal)
            footerView.secondaryButton.setButtonStyle(style: .tertiary)
            footerView.secondaryButton.setButtonAction(target: self, selector: #selector(createPollDraftButtonPressed))

            footerView.frame.size.height += PollFooterView.heightForOption
            footerView.secondaryButtonContainerView.isHidden = false
        }

        checkIfPollIsReadyToCreate()
        self.tableView.tableFooterView = footerView
    }

    func createPollButtonPressed() {
        createPoll(asDraft: false)
    }

    func createPollDraftButtonPressed() {
        createPoll(asDraft: true)
    }

    func createPoll(asDraft: Bool) {
        let resultMode: NCPollResultMode = anonymousPollSwitch.isOn ? .hidden : .public
        let maxVotes: Int = multipleAnswersSwitch.isOn ? 0 : 1

        showPollCreationUI()
        NCAPIController.sharedInstance().createPoll(withQuestion: question, options: options, resultMode: resultMode, maxVotes: maxVotes, inRoom: room.token, asDraft: asDraft, for: room.account) { _, error, _ in
            self.removePollCreationUI()
            if error != nil {
                self.showCreationError()
            } else if asDraft {
                self.showDraftCreationSuccess()
            } else {
                self.close()
            }
        }
    }

    func saveEditedPollDraftButtonPressed() {
        guard let draftId = editingDraftId else { return }

        let resultMode: NCPollResultMode = anonymousPollSwitch.isOn ? .hidden : .public
        let maxVotes: Int = multipleAnswersSwitch.isOn ? 0 : 1

        showPollCreationUI()
        NCAPIController.sharedInstance().editPollDraft(withId: draftId, question: question, options: options, resultMode: resultMode, maxVotes: maxVotes, inRoom: room.token, for: room.account) { _, error, _ in
            self.removePollCreationUI()
            if error != nil {
                self.showEditionError()
            } else {
                self.editingDraftId = nil
                self.refreshPollCreationView()
                self.presentPollDraftsView()
            }
        }
    }

    func checkIfPollIsReadyToCreate() {
        disablePollCreationButtons()

        if !question.isEmpty && options.filter({!$0.isEmpty}).count >= 2 {
            enablePollCreationButtons()
        }
    }

    func initPollCreationView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.keyboardDismissMode = UIScrollView.KeyboardDismissMode.onDrag
        self.tableView.register(TextFieldTableViewCell.self, forCellReuseIdentifier: TextFieldTableViewCell.identifier)
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
                if let optionCell = self.tableView.cellForRow(at: indexPath) as? TextFieldTableViewCell {
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
        if indexPath.section == PollCreationSection.kPollCreationSectionQuestion.rawValue {
            let textInputCell: TextFieldTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: TextFieldTableViewCell.identifier)
            textInputCell.textField.delegate = self
            textInputCell.textField.placeholder = NSLocalizedString("Ask a question", comment: "")
            textInputCell.textField.tag = kQuestionTextFieldTag
            textInputCell.textField.text = question
            return textInputCell
        } else if indexPath.section == PollCreationSection.kPollCreationSectionOptions.rawValue {
            if indexPath.row == options.count {
                let actionCell = tableView.dequeueOrCreateCell(withIdentifier: "PollSettingCellIdentifier")
                actionCell.textLabel?.text = NSLocalizedString("Add answer", comment: "")
                return actionCell
            } else if indexPath.row < options.count {
                let textInputCell: TextFieldTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: TextFieldTableViewCell.identifier)
                textInputCell.textField.delegate = self
                textInputCell.textField.placeholder = NSLocalizedString("Answer", comment: "") + " " + String(indexPath.row + 1)
                textInputCell.textField.tag = indexPath.row
                textInputCell.textField.text = options[indexPath.row]
                return textInputCell
            }
        } else if indexPath.section == PollCreationSection.kPollCreationSectionSettings.rawValue {
            if indexPath.row == PollSetting.kPollSettingPrivate.rawValue {
                let actionCell = tableView.dequeueOrCreateCell(withIdentifier: "PollSettingCellIdentifier")
                actionCell.textLabel?.text = NSLocalizedString("Anonymous poll", comment: "")
                actionCell.accessoryView = anonymousPollSwitch
                return actionCell
            } else if indexPath.row == PollSetting.kPollSettingMultiple.rawValue {
                let actionCell = tableView.dequeueOrCreateCell(withIdentifier: "PollSettingCellIdentifier")
                actionCell.textLabel?.text = NSLocalizedString("Multiple answers", comment: "")
                actionCell.accessoryView = multipleAnswersSwitch
                return actionCell
            }
        }
        return UITableViewCell()
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
