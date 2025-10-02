//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

enum RoomCreationSection: Int {
    case kRoomNameSection = 0
    case kRoomDescriptionSection
    case kRoomParticipantsSection
    case kRoomVisibilitySection
}

enum RoomVisibilityOption: Int {
    case kAllowGuestsOption = 0
    case kPasswordProtectionOption
    case kOpenConversationOption
    case kOpenConversationGuestsOption
}

@objcMembers class RoomCreationTableViewController: UITableViewController,
                                                    UINavigationControllerDelegate,
                                                    UIImagePickerControllerDelegate,
                                                    UITextFieldDelegate,
                                                    AvatarEditViewDelegate,
                                                    AddParticipantsTableViewControllerDelegate,
                                                    EmojiAvatarPickerViewControllerDelegate,
                                                    TextViewTableViewCellDelegate,
                                                    TOCropViewControllerDelegate {

    var account: TalkAccount
    var headerView = AvatarEditView()
    var createButton = UIBarButtonItem()
    var modifyingView = UIActivityIndicatorView()
    var imagePicker: UIImagePickerController?
    var participantsSectionHeaderView = HeaderWithButton()

    var roomName = ""
    var roomDescription = ""
    var roomParticipants: [NCUser] = []
    var isPublic = false
    var roomPassword = ""
    var isOpenConversation = false
    var isOpenForGuests = false

    var selectedAvatarImage: UIImage?
    var selectedEmoji: String?
    var selectedEmojiBackgroundColor: String?
    var selectedEmojiImage: UIImage?

    let kRoomNameTextFieldTag = 99
    let kPasswordTextFieldTag = 98
    var setPasswordAction = UIAlertAction()

    var roomCreationGroup = DispatchGroup()
    var roomCreationErrors: [String] = []

    init(account: TalkAccount) {
        self.account = account
        self.headerView = AvatarEditView()
        super.init(style: .insetGrouped)

        self.headerView.delegate = self
        self.headerView.scopeButton.isHidden = true
        self.headerView.nameLabel.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("New conversation", comment: "")

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))

        if #unavailable(iOS 26.0) {
            self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
        }

        self.tableView.register(TextFieldTableViewCell.self, forCellReuseIdentifier: TextFieldTableViewCell.identifier)
        self.tableView.register(TextViewTableViewCell.self, forCellReuseIdentifier: TextViewTableViewCell.identifier)
        self.tableView.register(UINib(nibName: kContactsTableCellNibName, bundle: nil), forCellReuseIdentifier: kContactCellIdentifier)
        self.tableView.tableHeaderView = self.headerView
        self.tableView.keyboardDismissMode = .onDrag

        self.participantsSectionHeaderView.button.setTitle(NSLocalizedString("Edit", comment: "Edit a message or room participants"), for: .normal)
        self.participantsSectionHeaderView.button.addTarget(self, action: #selector(editParticipantsButtonPressed), for: .touchUpInside)

        self.createButton = UIBarButtonItem(title: NSLocalizedString("Create", comment: ""), style: .done, target: self, action: #selector(createRoom))
        self.createButton.accessibilityHint = NSLocalizedString("Double tap to end editing profile", comment: "")
        self.createButton.isEnabled = false
        self.navigationItem.rightBarButtonItem = self.createButton

        self.modifyingView.color = NCAppBranding.themeTextColor()

        self.headerView.editView.isHidden = !NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityConversationAvatars, forAccountId: self.account.accountId)
        // Need to have an explicit size here for the header view
        let size = self.headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.headerView.frame = CGRect(origin: .zero, size: size)
        self.updateHeaderView()
    }

    func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    func updateHeaderView() {
        if self.selectedAvatarImage != nil {
            self.headerView.avatarImageView.image = self.selectedAvatarImage
        } else if self.selectedEmojiImage != nil {
            self.headerView.avatarImageView.image = self.selectedEmojiImage
        } else {
            self.headerView.avatarImageView.setGroupAvatar()
        }

        self.headerView.trashButton.isHidden = self.selectedAvatarImage == nil && self.selectedEmojiImage == nil
    }

    func getRoomCreationSections() -> [Int] {
        var sections = [Int]()

        // Room name section
        sections.append(RoomCreationSection.kRoomNameSection.rawValue)

        // Room description section
        if NCDatabaseManager.sharedInstance().serverHasTalkCapability(kCapabilityRoomDescription, forAccountId: self.account.accountId) {
            sections.append(RoomCreationSection.kRoomDescriptionSection.rawValue)
        }

        // Room participants section
        sections.append(RoomCreationSection.kRoomParticipantsSection.rawValue)

        // Room visibility section
        sections.append(RoomCreationSection.kRoomVisibilitySection.rawValue)

        return sections
    }

    func getRoomVisibilityOptions() -> [Int] {
        var options = [Int]()

        // Allow guest option
        options.append(RoomVisibilityOption.kAllowGuestsOption.rawValue)

        // Password protection option
        if self.isPublic {
            options.append(RoomVisibilityOption.kPasswordProtectionOption.rawValue)
        }

        // Open conversation option
        options.append(RoomVisibilityOption.kOpenConversationOption.rawValue)

        // Open conversation for guests option
        if self.isOpenConversation {
            options.append(RoomVisibilityOption.kOpenConversationGuestsOption.rawValue)
        }

        return options
    }

    func showModifyingView() {
        modifyingView.startAnimating()
        self.headerView.changeButtonState(to: false)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: modifyingView)
        self.tableView.isUserInteractionEnabled = false
    }

    func removeModifyingView() {
        modifyingView.stopAnimating()
        self.headerView.changeButtonState(to: true)
        self.navigationItem.rightBarButtonItem = createButton
        self.tableView.isUserInteractionEnabled = true
    }

    func removeSelectedAvatar() {
        self.selectedAvatarImage = nil
        self.selectedEmoji = nil
        self.selectedEmojiBackgroundColor = nil
        self.selectedEmojiImage = nil
    }

    func allowGuestValueChanged(_ sender: Any?) {
        if let optionSwitch = sender as? UISwitch {
            self.isPublic = optionSwitch.isOn
            self.updateVisibilitySection()
        }
    }

    func openConversationValueChanged(_ sender: Any?) {
        if let optionSwitch = sender as? UISwitch {
            self.isOpenConversation = optionSwitch.isOn
            self.updateVisibilitySection()
        }
    }

    func openForGuestsValueChanged(_ sender: Any?) {
        if let optionSwitch = sender as? UISwitch {
            self.isOpenForGuests = optionSwitch.isOn
            self.updateVisibilitySection()
        }
    }

    func updateVisibilitySection() {
        let sections = self.getRoomCreationSections()
        if let index = sections.firstIndex(of: RoomCreationSection.kRoomVisibilitySection.rawValue) {
            self.tableView.reloadSections([index], with: .automatic)
        }
    }

    // MARK: - Room creation

    func createRoom() {
        self.showModifyingView()
        self.roomCreationErrors = []

        // Create conversation
        let roomType: NCRoomType = self.isPublic ? .public : .group
        NCAPIController.sharedInstance().createRoom(forAccount: self.account, withInvite: nil, ofType: roomType, andName: self.roomName) { room, error in
            if let error {
                NCUtils.log(String(format: "Failed to create room. Error: %@", error.localizedDescription))
                self.roomCreationErrors.append(error.localizedDescription)

                self.removeModifyingView()
                self.presentRoomCreationFailedErrorDialog()
            } else if let room {
                self.setAdditionalRoomSettings(token: room.token)
            }
        }
    }

    func setAdditionalRoomSettings(token: String) {

        self.roomCreationGroup = DispatchGroup()
        self.roomCreationErrors = []

        // Room avatar
        if self.selectedAvatarImage != nil {
            self.roomCreationGroup.enter()
            NCAPIController.sharedInstance().setAvatarForRoomWithToken(token, image: self.selectedAvatarImage, account: self.account) { error in
                if let error {
                    NCUtils.log(String(format: "Failed to set room avatar. Error: %@", error.localizedDescription))
                    self.roomCreationErrors.append(error.localizedDescription)
                }

                self.roomCreationGroup.leave()
            }
        } else if self.selectedEmojiImage != nil {
            self.roomCreationGroup.enter()
            NCAPIController.sharedInstance().setEmojiAvatarForRoomWithToken(token, withEmoji: self.selectedEmoji, andColor: self.selectedEmojiBackgroundColor, account: self.account) { error in
                if let error {
                    NCUtils.log(String(format: "Failed to set room emoji avatar. Error: %@", error.localizedDescription))
                    self.roomCreationErrors.append(error.localizedDescription)
                }

                self.roomCreationGroup.leave()
            }
        }

        // Room description
        if !self.roomDescription.isEmpty {
            self.roomCreationGroup.enter()
            NCAPIController.sharedInstance().setRoomDescription(self.roomDescription, forRoom: token, forAccount: account) { error in
                if let error {
                    NCUtils.log(String(format: "Failed to set room description. Error: %@", error.localizedDescription))
                    self.roomCreationErrors.append(error.localizedDescription)
                }

                self.roomCreationGroup.leave()
            }
        }

        // Room participants
        for participant in roomParticipants {
            self.roomCreationGroup.enter()

            Task {
                do {
                    try await NCAPIController.sharedInstance().addParticipant(participant.userId, ofType: participant.source as String?, toRoom: token, forAccount: account)
                } catch {
                    NCUtils.log(String(format: "Failed to add participant. Error: %@", error.localizedDescription))
                    self.roomCreationErrors.append(error.localizedDescription)
                }

                self.roomCreationGroup.leave()
            }
        }

        // Room password
        if !self.roomPassword.isEmpty {
            self.roomCreationGroup.enter()
            NCAPIController.sharedInstance().setPassword(self.roomPassword, forRoom: token, forAccount: self.account) { error, _ in
                if let error {
                    NCUtils.log(String(format: "Failed to set room password. Error: %@", error.localizedDescription))
                    self.roomCreationErrors.append(error.localizedDescription)
                }

                self.roomCreationGroup.leave()
            }
        }

        // Room listable scope
        if self.isOpenConversation {
            self.roomCreationGroup.enter()
            let listableScope: NCRoomListableScope = self.isOpenForGuests ? .everyone : .regularUsersOnly

            Task {
                do {
                    try await NCAPIController.sharedInstance().setListableScope(scope: listableScope, forRoom: token, forAccount: self.account)
                } catch {
                    self.roomCreationErrors.append(error.localizedDescription)
                }

                self.roomCreationGroup.leave()
            }
        }

        self.roomCreationGroup.notify(queue: .main) {
            self.removeModifyingView()

            if self.roomCreationErrors.isEmpty {
                NotificationCenter.default.post(name: NSNotification.Name.NCRoomCreated, object: self, userInfo: ["token": token])
            } else {
                self.presentRoomCreationFailedErrorDialog()
            }
        }
    }

    func presentRoomCreationFailedErrorDialog() {
        let alert = UIAlertController(title: NSLocalizedString("Conversation creation failed", comment: ""),
                                      message: self.roomCreationErrors.joined(separator: "\n"),
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))

        self.present(alert, animated: true)
    }

    // MARK: - Room participants

    func editParticipantsButtonPressed() {
        if let editParticipantsVC = AddParticipantsTableViewController(participants: self.roomParticipants) {
            editParticipantsVC.delegate = self
            self.present(NCNavigationController(rootViewController: editParticipantsVC), animated: true)
        }
    }

    // MARK: - Room password

    func presentRoomPasswordOptions() {
        let alertTitle = self.roomPassword.isEmpty ? NSLocalizedString("Set password", comment: "") : NSLocalizedString("Set new password", comment: "")
        let passwordDialog = UIAlertController(title: alertTitle, message: nil, preferredStyle: .alert)

        passwordDialog.addTextField { [weak self] textField in
            guard let self else { return }
            textField.tag = self.kPasswordTextFieldTag
            textField.placeholder = NSLocalizedString("Password", comment: "")
            textField.isSecureTextEntry = true
            textField.delegate = self
        }

        let actionTitle = self.roomPassword.isEmpty ? NSLocalizedString("OK", comment: "") : NSLocalizedString("Change password", comment: "")
        self.setPasswordAction = UIAlertAction(title: actionTitle, style: .default) { _ in
            self.roomPassword = passwordDialog.textFields?[0].text?.trimmingCharacters(in: .whitespaces) ?? ""
            self.updateVisibilitySection()
        }
        self.setPasswordAction.isEnabled = false
        passwordDialog.addAction(self.setPasswordAction)

        if !self.roomPassword.isEmpty {
            passwordDialog.addAction(UIAlertAction(title: NSLocalizedString("Remove password", comment: ""), style: .destructive, handler: { _ in
                self.roomPassword = ""
                self.updateVisibilitySection()
            }))
        }

        passwordDialog.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))

        self.present(passwordDialog, animated: true)
    }

    // MARK: - TableView

    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.getRoomCreationSections().count
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 40
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let sections = getRoomCreationSections()
        let roomCreationSection = sections[section]
        if roomCreationSection == RoomCreationSection.kRoomParticipantsSection.rawValue {
            self.participantsSectionHeaderView.label.text = NSLocalizedString("Participants", comment: "").uppercased()
            self.participantsSectionHeaderView.button.isHidden = self.roomParticipants.isEmpty
            return participantsSectionHeaderView
        }

        return nil
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sections = getRoomCreationSections()
        let roomCreationSection = sections[section]
        if roomCreationSection == RoomCreationSection.kRoomParticipantsSection.rawValue {
            return self.roomParticipants.isEmpty ? 1 : self.roomParticipants.count
        } else if roomCreationSection == RoomCreationSection.kRoomVisibilitySection.rawValue {
            return self.getRoomVisibilityOptions().count
        }

        return 1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let sections = getRoomCreationSections()
        let roomCreationSection = sections[indexPath.section]

        if roomCreationSection == RoomCreationSection.kRoomNameSection.rawValue {
            let textInputCell: TextFieldTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: TextFieldTableViewCell.identifier)
            textInputCell.textField.tag = kRoomNameTextFieldTag
            textInputCell.textField.delegate = self
            textInputCell.textField.text = self.roomName
            textInputCell.textField.becomeFirstResponder()
            return textInputCell
        } else if roomCreationSection == RoomCreationSection.kRoomDescriptionSection.rawValue {
            let descriptionCell: TextViewTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: TextViewTableViewCell.identifier)
            descriptionCell.textView.text = self.roomDescription
            descriptionCell.textView.isEditable = true
            descriptionCell.delegate = self
            descriptionCell.characterLimit = 500
            descriptionCell.selectionStyle = .none
            return descriptionCell
        } else if roomCreationSection == RoomCreationSection.kRoomParticipantsSection.rawValue {
            if self.roomParticipants.isEmpty {
                let addParticipantCell = tableView.dequeueOrCreateCell(withIdentifier: "AddParticipantCellIdentifier")
                addParticipantCell.textLabel?.text = NSLocalizedString("Add participants", comment: "")
                addParticipantCell.imageView?.image = UIImage(systemName: "person.badge.plus")
                addParticipantCell.imageView?.tintColor = .secondaryLabel
                addParticipantCell.imageView?.contentMode = .scaleAspectFit
                return addParticipantCell
            } else {
                let participant = self.roomParticipants[indexPath.row]
                let participantCell: ContactsTableViewCell = tableView.dequeueOrCreateCell(withIdentifier: kContactCellIdentifier)

                participantCell.labelTitle.text = participant.name

                let participantType = participant.source as String
                let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
                participantCell.contactImage.setActorAvatar(forId: participant.userId, withType: participantType, withDisplayName: participant.name, withRoomToken: nil, using: activeAccount)

                return participantCell
            }
        } else if roomCreationSection == RoomCreationSection.kRoomVisibilitySection.rawValue {
            let options = getRoomVisibilityOptions()
            let option = options[indexPath.row]
            var roomVisibilityOptionCell = UITableViewCell()
            switch option {
            case RoomVisibilityOption.kAllowGuestsOption.rawValue:
                roomVisibilityOptionCell = tableView.dequeueOrCreateCell(withIdentifier: "AllowGuestsCellIdentifier")
                roomVisibilityOptionCell.textLabel?.text = NSLocalizedString("Allow guests to join this conversation via link", comment: "")
                let optionSwicth = UISwitch()
                optionSwicth.isOn = self.isPublic
                optionSwicth.addTarget(self, action: #selector(allowGuestValueChanged(_:)), for: .valueChanged)
                roomVisibilityOptionCell.accessoryView = optionSwicth
                roomVisibilityOptionCell.imageView?.image = UIImage(named: "link")?.withRenderingMode(.alwaysTemplate)
            case RoomVisibilityOption.kPasswordProtectionOption.rawValue:
                roomVisibilityOptionCell = tableView.dequeueOrCreateCell(withIdentifier: "SetPasswordCellIdentifier")
                roomVisibilityOptionCell.textLabel?.text = self.roomPassword.isEmpty ? NSLocalizedString("Set password", comment: "") : NSLocalizedString("Change password", comment: "")
                roomVisibilityOptionCell.imageView?.image = self.roomPassword.isEmpty ? UIImage(systemName: "lock.open") : UIImage(systemName: "lock")
            case RoomVisibilityOption.kOpenConversationOption.rawValue:
                roomVisibilityOptionCell = tableView.dequeueOrCreateCell(withIdentifier: "OpenConversationCellIdentifier")
                roomVisibilityOptionCell.textLabel?.text = NSLocalizedString("Open conversation to registered users", comment: "")
                let optionSwicth = UISwitch()
                optionSwicth.isOn = self.isOpenConversation
                optionSwicth.addTarget(self, action: #selector(openConversationValueChanged(_:)), for: .valueChanged)
                roomVisibilityOptionCell.accessoryView = optionSwicth
                roomVisibilityOptionCell.imageView?.image = UIImage(systemName: "list.bullet")
            case RoomVisibilityOption.kOpenConversationGuestsOption.rawValue:
                roomVisibilityOptionCell = tableView.dequeueOrCreateCell(withIdentifier: "OpenConversationGuestsCellIdentifier")
                roomVisibilityOptionCell.textLabel?.text = NSLocalizedString("Also open to guest app users", comment: "")
                let optionSwicth = UISwitch()
                optionSwicth.isOn = self.isOpenForGuests
                optionSwicth.addTarget(self, action: #selector(openForGuestsValueChanged(_:)), for: .valueChanged)
                roomVisibilityOptionCell.accessoryView = optionSwicth
                roomVisibilityOptionCell.imageView?.image = UIImage(systemName: "list.bullet")
                roomVisibilityOptionCell.imageView?.isHidden = true
            default:
                break
            }

            roomVisibilityOptionCell.selectionStyle = .none
            roomVisibilityOptionCell.imageView?.tintColor = .secondaryLabel
            roomVisibilityOptionCell.imageView?.contentMode = .scaleAspectFit
            roomVisibilityOptionCell.textLabel?.numberOfLines = 0

            return roomVisibilityOptionCell
        }

        return UITableViewCell()
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let sections = getRoomCreationSections()
        let roomCreationSection = sections[section]

        if roomCreationSection == RoomCreationSection.kRoomNameSection.rawValue {
            return NSLocalizedString("Name", comment: "")
        } else if roomCreationSection == RoomCreationSection.kRoomDescriptionSection.rawValue {
            return NSLocalizedString("Description", comment: "")
        } else if roomCreationSection == RoomCreationSection.kRoomVisibilitySection.rawValue {
            return NSLocalizedString("Visibility", comment: "Conversation visibility settings")
        }

        return nil
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sections = getRoomCreationSections()
        let roomCreationSection = sections[indexPath.section]

        if roomCreationSection == RoomCreationSection.kRoomParticipantsSection.rawValue {
            if self.roomParticipants.isEmpty {
                self.editParticipantsButtonPressed()
            }
        } else if roomCreationSection == RoomCreationSection.kRoomVisibilitySection.rawValue {
            let options = getRoomVisibilityOptions()
            let option = options[indexPath.row]

            if option == RoomVisibilityOption.kPasswordProtectionOption.rawValue {
                self.presentRoomPasswordOptions()
            }

        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: - AddParticipantsTableViewController Delegate

    func addParticipantsTableViewController(_ viewController: AddParticipantsTableViewController!, wantsToAdd participants: [NCUser]!) {
        self.roomParticipants = participants
        let sections = self.getRoomCreationSections()
        if let index = sections.firstIndex(of: RoomCreationSection.kRoomParticipantsSection.rawValue) {
            self.tableView.reloadSections([index], with: .automatic)
        }
    }

    // MARK: - Present camera/photo library

    func checkAndPresentCamera() {
        // https://stackoverflow.com/a/20464727/2512312
        let mediaType: String = AVMediaType.video.rawValue
        let authStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType(mediaType))
        if authStatus == AVAuthorizationStatus.authorized {
            self.presentCamera()
            return
        } else if authStatus == AVAuthorizationStatus.notDetermined {
            AVCaptureDevice.requestAccess(for: AVMediaType(mediaType)) { granted in
                if granted {
                    self.presentCamera()
                }
            }
            return
        }

        let alertTitle = NSLocalizedString("Could not access camera", comment: "")
        let alertMessage = NSLocalizedString("Camera access is not allowed. Check your settings.", comment: "")
        NCUserInterfaceController.sharedInstance().presentAlert(withTitle: alertTitle, withMessage: alertMessage)
    }

    func presentCamera() {
        DispatchQueue.main.async {
            self.imagePicker = UIImagePickerController()
            if let imagePicker = self.imagePicker {
                imagePicker.sourceType = .camera
                imagePicker.delegate = self
                self.present(imagePicker, animated: true)
            }
        }
    }

    func presentPhotoLibrary() {
        DispatchQueue.main.async {
            self.imagePicker = UIImagePickerController()
            if let imagePicker = self.imagePicker {
                imagePicker.sourceType = .photoLibrary
                imagePicker.delegate = self
                self.present(imagePicker, animated: true)
            }
        }
    }

    func presentEmojiAvatarPicker() {
        DispatchQueue.main.async {
            let emojiAvatarPickerVC = EmojiAvatarPickerViewController()
            emojiAvatarPickerVC.delegate = self
            let emojiAvatarPickerNC = UINavigationController(rootViewController: emojiAvatarPickerVC)
            self.present(emojiAvatarPickerNC, animated: true, completion: nil)
        }
    }

    // MARK: - UIImagePickerController Delegate

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let mediaType = info[UIImagePickerController.InfoKey.mediaType] as? String
        if mediaType == "public.image" {
            let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage
            self.dismiss(animated: true) {
                if let image = image {
                    let cropViewController = TOCropViewController(croppingStyle: TOCropViewCroppingStyle.circular, image: image)
                    cropViewController.delegate = self
                    self.present(cropViewController, animated: true)
                }
            }
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.dismiss(animated: true, completion: nil)
    }

    // MARK: - TextViewTableViewCellDelegate

    func textViewCellTextViewDidChange(_ cell: TextViewTableViewCell) {
        DispatchQueue.main.async {
            self.tableView?.beginUpdates()
            self.tableView?.endUpdates()
            self.roomDescription = cell.textView.text ?? ""
        }
    }

    func textViewCellDidEndEditing(_ cell: TextViewTableViewCell) {
        self.roomDescription = cell.textView.text ?? ""
    }

    func textViewCellDidExceedCharacterLimit(_ cell: TextViewTableViewCell) {
        NotificationPresenter.shared().present(
            text: NSLocalizedString("Description cannot be longer than 500 characters", comment: ""),
            dismissAfterDelay: 3.0,
            includedStyle: .warning)
    }

    // MARK: - TOCROPViewControllerDelegate

    func cropViewController(_ cropViewController: TOCropViewController, didCropTo image: UIImage, with cropRect: CGRect, angle: Int) {
        // Fixes weird iOS 13 bug: https://github.com/TimOliver/TOCropViewController/issues/365
        cropViewController.transitioningDelegate = nil
        cropViewController.dismiss(animated: true) {
            self.removeSelectedAvatar()
            self.selectedAvatarImage = image
            self.updateHeaderView()
        }
    }

    func cropViewController(_ cropViewController: TOCropViewController, didFinishCancelled cancelled: Bool) {
        // Fixes weird iOS 13 bug: https://github.com/TimOliver/TOCropViewController/issues/365
        cropViewController.transitioningDelegate = nil
        cropViewController.dismiss(animated: true)
    }

    // MARK: - AvaterEditViewDelegate

    func avatarEditViewPresentCamera(_ controller: AvatarEditView?) {
        self.checkAndPresentCamera()
    }

    func avatarEditViewPresentPhotoLibrary(_ controller: AvatarEditView?) {
        self.presentPhotoLibrary()
    }

    func avatarEditViewPresentEmojiAvatarPicker(_ controller: AvatarEditView?) {
        self.presentEmojiAvatarPicker()
    }

    func avatarEditViewRemoveAvatar(_ controller: AvatarEditView?) {
        self.removeSelectedAvatar()
        self.updateHeaderView()
    }

    // MARK: - EmojiAvatarPickerViewControllerDelegate

    func didSelectEmoji(emoji: NSString, color: NSString, image: UIImage) {
        self.removeSelectedAvatar()
        self.selectedEmoji = emoji as String
        self.selectedEmojiBackgroundColor = color as String
        self.selectedEmojiImage = image
        self.updateHeaderView()
    }

    // MARK: - UITextField delegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        if textField.tag == kRoomNameTextFieldTag {
            textField.resignFirstResponder()
            textField.becomeFirstResponder()
            self.roomName = ""
            self.createButton.isEnabled = false
        }

        return true
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let currentText = textField.text ?? ""
        guard let stringRange = Range(range, in: currentText) else { return false }
        let updatedText = currentText.replacingCharacters(in: stringRange, with: string).trimmingCharacters(in: .whitespaces)

        if textField.tag == kRoomNameTextFieldTag {
            self.roomName = updatedText
            self.createButton.isEnabled = !updatedText.isEmpty
        } else if textField.tag == kPasswordTextFieldTag {
            let hasAllowedLength = updatedText.count <= 200
            self.setPasswordAction.isEnabled = hasAllowedLength && !updatedText.isEmpty
            return hasAllowedLength
        }

        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField.tag == kRoomNameTextFieldTag, let text = textField.text {
            let roomName = text.trimmingCharacters(in: CharacterSet.whitespaces)
            self.roomName = roomName
            self.createButton.isEnabled = !roomName.isEmpty
        }
    }
}
