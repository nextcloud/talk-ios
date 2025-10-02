//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

class ThreadCreationViewController: InputbarViewController, UITextFieldDelegate {

    // MARK: - Private var
    private var threadCreationContentView = UIView()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = NSLocalizedString("Create a thread", comment: "")
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let titleTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = NSLocalizedString("Thread title", comment: "")
        textField.font = UIFont.preferredFont(forTextStyle: .body)
        textField.borderStyle = .roundedRect
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    // MARK: - Init
    public init?(room: NCRoom, account: TalkAccount) {
        super.init(forRoom: room, withAccount: account, withView: self.threadCreationContentView)

        self.textView.maxNumberOfLines = 2

        self.threadCreationContentView.addSubview(self.titleLabel)
        NSLayoutConstraint.activate([
            self.titleLabel.topAnchor.constraint(equalTo: self.threadCreationContentView.safeAreaLayoutGuide.topAnchor, constant: 16),
            self.titleLabel.leadingAnchor.constraint(equalTo: self.threadCreationContentView.leadingAnchor, constant: 16),
            self.titleLabel.trailingAnchor.constraint(equalTo: self.threadCreationContentView.trailingAnchor, constant: -16)
        ])

        self.threadCreationContentView.addSubview(self.titleTextField)
        NSLayoutConstraint.activate([
            self.titleTextField.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 8),
            self.titleTextField.leadingAnchor.constraint(equalTo: self.threadCreationContentView.leadingAnchor, constant: 16),
            self.titleTextField.trailingAnchor.constraint(equalTo: self.threadCreationContentView.trailingAnchor, constant: -16)
        ])

    }

    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemBackground

        self.setupSheetPresentation()
        self.setupDismissKeyboardOnTap()
        self.titleTextField.delegate = self
    }

    private func setupSheetPresentation() {
        guard let sheet = sheetPresentationController else { return }

        sheet.detents = [
            .custom { _ in 160 }
        ]
        sheet.prefersGrabberVisible = true
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false

        isModalInPresentation = false
    }

    // MARK: - Thread creation

    public override func didPressRightButton(_ sender: Any?) {
        self.createThread()
    }

    private func createThread() {
        guard let title = self.titleTextField.text, !title.isEmpty else {
            return
        }

        let messageParameters = NCMessageParameter.messageParametersJSONString(from: self.mentionsDict) ?? ""
        let message = NCChatMessage()
        message.message = self.replaceMentionsDisplayNamesWithMentionsKeysInMessage(message: self.textView.text, parameters: messageParameters)
        message.messageParametersJSONString = messageParameters

        NCAPIController.sharedInstance().sendChatMessage(message.sendingMessage, toRoom: room.token, threadTitle: title, replyTo: -1, referenceId: nil, silently: false, for: account) { error in
            if error == nil {
                NCDatabaseManager.sharedInstance().updateHasThreads(forAccountId: self.account.accountId, with: true)
                self.dismiss(animated: true)
            } else {
                NotificationPresenter.shared().present(text: NSLocalizedString("An error occurred while creating the thread", comment: ""), dismissAfterDelay: 5.0, includedStyle: .error)
            }
        }
    }

    // MARK: - Keyboard Handling

    private func setupDismissKeyboardOnTap() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapOutside))
        tapGesture.cancelsTouchesInView = false
        self.threadCreationContentView.addGestureRecognizer(tapGesture)
    }

    @objc private func handleTapOutside() {
        self.threadCreationContentView.endEditing(true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
