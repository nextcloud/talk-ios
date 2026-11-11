//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import NextcloudKit

@objc protocol LoginViewControllerDelegate: AnyObject {
    func loginViewControllerDidFinish()
}

@objcMembers
class LoginViewController: UIViewController, UITextFieldDelegate, NCCertificateDelegate, DetailedOptionsSelectorTableViewControllerDelegate, QRScannerViewControllerDelegate {

    weak var delegate: LoginViewControllerDelegate?

    private var loginFlowController: LoginFlowController?
    private var pendingOnetimeLogin: OnetimeLogin?

    private struct OnetimeLogin {
        let serverURL: String
        let user: String
        let onetimeToken: String
    }
    var importedNextcloudFilesAccounts: [NKShareAccounts.DataAccounts] = []

    @IBOutlet weak var appLogoImageView: UIImageView!
    @IBOutlet weak var serverTextField: UITextField!
    @IBOutlet weak var activityIndicatorView: UIActivityIndicatorView!
    @IBOutlet weak var serverLabel: UILabel!
    @IBOutlet weak var loginButton: UIButton!
    @IBOutlet weak var importAccountButton: UIButton!
    @IBOutlet weak var qrCodeButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton!

    @IBAction func loginButtonPressed(_ sender: Any) {
        startLoginProcess()
    }
    @IBAction func importAccountButtonPressed(_ sender: Any) {
        presentImportedAccountsSelector()
    }
    @IBAction func qrCodeButtonPressed(_ sender: Any) {
        let qrScannerViewController = QRScannerViewController()
        qrScannerViewController.delegate = self
        present(qrScannerViewController, animated: true)
    }
    @IBAction func cancelButtonPressed(_ sender: Any) {
        dismiss(animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Login view background color
        view.backgroundColor = NCAppBranding.brandColor()

        // App logo
        self.appLogoImageView.image = UIImage(named: "loginLogo")

        // Server TextField
        serverTextField.delegate = self
        serverTextField.textColor = NCAppBranding.brandTextColor()
        serverTextField.tintColor = NCAppBranding.brandTextColor()
        serverTextField.layer.borderColor = NCAppBranding.brandTextColor().cgColor
        serverTextField.layer.borderWidth = 1
        serverTextField.layer.cornerRadius = 8
        serverTextField.layer.masksToBounds = true
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 40))
        serverTextField.leftView = paddingView
        serverTextField.leftViewMode = .always
        serverTextField.rightView = paddingView
        serverTextField.rightViewMode = .always
        serverTextField.attributedPlaceholder = NSAttributedString(
            string: NSLocalizedString("Server address https://…", comment: ""),
            attributes: [.foregroundColor: NCAppBranding.brandTextColor().withAlphaComponent(0.5)])
        serverLabel.textColor = NCAppBranding.brandTextColor()
        serverLabel.text = NSLocalizedString("This is the web address you use to access your server in your web browser.", comment: "")

        // Login button
        loginButton.setTitle(NSLocalizedString("Log in", comment: ""), for: .normal)

        // QR code button
        qrCodeButton.setTitle(NSLocalizedString("Scan QR code", comment: ""), for: .normal)
        qrCodeButton.isHidden = !QRScannerViewController.isDataScannerSupported()

        // Import account button
        importAccountButton.setTitle(NSLocalizedString("Import account", comment: ""), for: .normal)

        // Buttons style
        [loginButton, qrCodeButton, importAccountButton].forEach { button in
            button.backgroundColor = NCAppBranding.brandColor()
            button.layer.borderColor = NCAppBranding.brandTextColor().cgColor
            button.layer.cornerRadius = 12
            button.layer.borderWidth = 1
            button.clipsToBounds = true

            // Highlighted style
            button.setTitleColor(NCAppBranding.brandTextColor().withAlphaComponent(0.5), for: .highlighted)
            if let buttonImage = button.image(for: .normal) {
                button.setImage(buttonImage.withTintColor(NCAppBranding.brandTextColor().withAlphaComponent(0.5), renderingMode: .alwaysOriginal), for: .highlighted)
            }
        }

        // Activity indicator
        activityIndicatorView.color = NCAppBranding.brandTextColor()
        activityIndicatorView.isHidden = true

        // Cancel button
        cancelButton.setTitle(NSLocalizedString("Cancel", comment: ""), for: .normal)
        cancelButton.setTitleColor(NCAppBranding.brandTextColor(), for: .normal)
        cancelButton.isHidden = !(multiAccountEnabled.boolValue && NCDatabaseManager.sharedInstance().numberOfAccounts() > 0)

        // Check for Nextcloud Files app accounts
        checkFilesAppAccounts()

        // A forced domain can't be changed
        if forceDomain.boolValue {
            serverTextField.text = domain
            serverTextField.isHidden = true
            serverLabel.isHidden = true
            loginButton.setTitleColor(NCAppBranding.brandTextColor().withAlphaComponent(0.5), for: .disabled)

            // Without the server field, the spinner moves into the login button
            let spinner: UIActivityIndicatorView = activityIndicatorView
            spinner.removeFromSuperview()
            spinner.translatesAutoresizingMaskIntoConstraints = false
            loginButton.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.trailingAnchor.constraint(equalTo: loginButton.trailingAnchor, constant: -16),
                spinner.centerYAnchor.constraint(equalTo: loginButton.centerYAnchor)
            ])
        }

        // Add tap gesture recognizer to dismiss keyboard
        view.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        )
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return NCAppBranding.statusBarStyleForBrandColor()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    // MARK: - Certificate delegate

    func trustedCertificateAccepted() {
        if let pendingOnetimeLogin {
            self.pendingOnetimeLogin = nil
            loginWithOnetimeToken(serverURL: pendingOnetimeLogin.serverURL, user: pendingOnetimeLogin.user, onetimeToken: pendingOnetimeLogin.onetimeToken)
        } else {
            loginButtonPressed(self)
        }
    }

    func trustedCertificateDenied() {
        pendingOnetimeLogin = nil
    }

    // MARK: - UITextField delegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        startLoginProcess()
        return true
    }

    func dismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: - Login

    func startLoginProcess() {
        guard let serverTextFieldText = serverTextField.text?.trimmingCharacters(in: .whitespaces),
              !serverTextFieldText.isEmpty else {
            serverTextField.becomeFirstResponder()
            return
        }

        startLoginProcess(serverURL: serverTextFieldText, user: nil)
    }

    func startLoginProcess(serverURL: String, user: String?) {
        var normalizedServerURL = serverURL.lowercased()

        // Check whether baseUrl contain protocol. If not add https:// by default.
        if !normalizedServerURL.hasPrefix("https://"), !normalizedServerURL.hasPrefix("http://") {
            normalizedServerURL = "https://" + serverURL
        }

        // Remove trailing slash
        if normalizedServerURL.hasSuffix("/") {
            normalizedServerURL.removeLast()
        }

        // Check if valid URL
        if URL(string: normalizedServerURL) == nil {
            showAlert(
                title: NSLocalizedString("Invalid server address", comment: ""),
                message: NSLocalizedString("Please check that you entered a valid server address.", comment: ""))
            return
        }

        // Set normalized server URL string in text field
        serverTextField.text = normalizedServerURL

        // Remove stored cookies
        HTTPCookieStorage.shared.cookies?.forEach { cookie in
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }

        showLoginActivity(true)

        // Check if valid Nextcloud server
        NCAPIController.sharedInstance().getServerCapabilities(forServer: normalizedServerURL) { serverCapabilities, error in
            self.showLoginActivity(false)

            if let error {
                if error.underlyingError.code == NSURLErrorServerCertificateUntrusted {
                    DispatchQueue.main.async {
                        NCCertificate.shared
                            .presentViewControllerCertificate(
                                withError: error.underlyingError,
                                viewController: self,
                                delegate: self)
                    }
                } else {
                    self.showServerNotFoundAlert(withError: error.underlyingError.localizedDescription)
                }
            } else {
                if let serverCapabilities = serverCapabilities as? [String: Any], let capabilities = serverCapabilities["capabilities"] as? [String: Any] {
                    if let talk = capabilities["spreed"] as? [String: Any], let features = talk["features"] as? [String], !features.isEmpty {
                        if features.contains(TalkCapability.minimumRequired.rawValue) {
                            self.startLoginFlow(serverURL: normalizedServerURL, user: nil)
                        } else {
                            self.showAlert(
                                title: String(format: NSLocalizedString("%@ version not supported", comment: "{app name} version not supported"), talkAppName),
                                message: String(format: NSLocalizedString("Please update your server with the latest %@ version available.", comment: "Please update your server with the latest {app name} version available."), talkAppName))
                        }
                    } else {
                        self.showAlert(
                            title: String(format: NSLocalizedString("%@ not installed", comment: "{app name} is not installed"), talkAppName),
                            message: String(format: NSLocalizedString("It seems that %@ is not installed in your server.", comment: "It seems that {app name} is not installed in your server."), talkAppName))
                    }
                } else {
                    self.showServerNotFoundAlert(withError: nil)
                }
            }
        }
    }

    func startLoginFlow(serverURL: String, user: String?) {
        guard loginFlowController == nil else { return }

        showLoginActivity(true)

        let loginFlowController = LoginFlowController(serverUrl: serverURL, user: user, presentingViewController: self) { [weak self] outcome in
            guard let self else { return }

            self.loginFlowController = nil
            self.showLoginActivity(false)

            switch outcome {
            case .loggedIn:
                self.delegate?.loginViewControllerDidFinish()
            case .failed:
                self.showAlert(
                    title: NSLocalizedString("Could not start login", comment: ""),
                    message: NSLocalizedString("Please check your connection and try again.", comment: ""))
            case .cancelled:
                break
            }
        }

        self.loginFlowController = loginFlowController
        loginFlowController.start()
    }

    private func showLoginActivity(_ active: Bool) {
        // With a forced domain the spinner is inside the login button, which can't be pressed again meanwhile
        if forceDomain.boolValue {
            loginButton.isEnabled = !active
        }

        activityIndicatorView.isHidden = !active
        if active {
            activityIndicatorView.startAnimating()
        } else {
            activityIndicatorView.stopAnimating()
        }
    }

    private func isAllowedServer(_ serverURL: String) -> Bool {
        guard forceDomain.boolValue else { return true }

        let normalize = { (url: String) in url.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        return normalize(serverURL) == normalize(domain)
    }

    // MARK: - Files app accounts

    func checkFilesAppAccounts() {
        guard useAppsGroup.boolValue, NCUtils.isNextcloudAppInstalled(),
              let appsGroupFolderURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appsGroupIdentifier),
              let filesAccounts = NKShareAccounts().getShareAccount(at: appsGroupFolderURL, application: UIApplication.shared)
        else {
            importAccountButton.isHidden = true
            return
        }

        let talkAccounts = NCDatabaseManager.sharedInstance().allAccounts()
        for fileAccount in filesAccounts {
            var accountAlreadyIncluded = false
            for talkAccount in talkAccounts {
                if talkAccount.server.caseInsensitiveCompare(fileAccount.url) == .orderedSame,
                   talkAccount.user.caseInsensitiveCompare(fileAccount.user) == .orderedSame {
                    accountAlreadyIncluded = true
                }
            }
            if !accountAlreadyIncluded, isAllowedServer(fileAccount.url) {
                importedNextcloudFilesAccounts.append(fileAccount)
            }
        }

        importAccountButton.isHidden = importedNextcloudFilesAccounts.isEmpty
    }

    func presentImportedAccountsSelector() {
        var importedAccounts = [DetailedOption]()
        for filesAccount in importedNextcloudFilesAccounts {
            let option = DetailedOption()
            option.identifier = filesAccount.user
            if let name = filesAccount.name, !name.isEmpty {
                option.title = name
            } else {
                option.title = filesAccount.user
            }
            option.subtitle = filesAccount.url
            option.image = filesAccount.image

            importedAccounts.append(option)
        }

        let accountSelectorVC = DetailedOptionsSelectorTableViewController(accounts: importedAccounts, andStyle: .insetGrouped)
        accountSelectorVC.title = NSLocalizedString("Import account", comment: "")
        accountSelectorVC.delegate = self
        let accountSelectorNC = NCNavigationController(rootViewController: accountSelectorVC)
        self.present(accountSelectorNC, animated: true)
    }

    // MARK: - DetailedOptionSelector delegate

    func detailedOptionsSelector(_ viewController: DetailedOptionsSelectorTableViewController, didSelectOptionWithIdentifier option: DetailedOption) {
        dismiss(animated: true) {
            self.startLoginFlow(serverURL: option.subtitle, user: option.identifier)
        }
    }

    func detailedOptionsSelectorWasCancelled(_ viewController: DetailedOptionsSelectorTableViewController) {
        dismiss(animated: true)
    }

    // MARK: - Alerts

    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: {[weak self] _ in
            guard !forceDomain.boolValue else { return }
            self?.serverTextField.becomeFirstResponder()
        }))
        self.present(alert, animated: true)
    }

    func showQRCodeForOtherServerAlert() {
        let showAlert = { [weak self] in
            self?.showAlert(
                title: NSLocalizedString("Could not login with QR code", comment: ""),
                message: NSLocalizedString("This QR code can't be used with this app.", comment: ""))
        }

        // The scanner is still being dismissed, an alert can't be presented before that finishes
        if let transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: nil) { _ in showAlert() }
        } else {
            showAlert()
        }
    }

    func showServerNotFoundAlert(withError error: String?) {
        if isBrandedApp.boolValue {
            if let error {
                self.showAlert(
                    title: NSLocalizedString("Server not found", comment: ""),
                    message: String(format: "%@\n%@", error, NSLocalizedString("Please check that you entered the correct server address.", comment: "")))

            } else {
                self.showAlert(
                    title: NSLocalizedString("Server not found", comment: ""),
                    message: NSLocalizedString("Please check that you entered the correct server address.", comment: ""))
            }
        } else {
            if let error {
                self.showAlert(
                    title: NSLocalizedString("Nextcloud server not found", comment: ""),
                    message: String(format: "%@\n%@", error, NSLocalizedString("Please check that you entered the correct Nextcloud server address.", comment: "")))

            } else {
                self.showAlert(
                    title: NSLocalizedString("Nextcloud server not found", comment: ""),
                    message: NSLocalizedString("Please check that you entered the correct Nextcloud server address.", comment: ""))
            }
        }
    }

    // MARK: - QRScannerViewControllerDelegate

    func qrScanner(_ scanner: QRScannerViewController, didScanNextcloudLogin serverURL: String, user: String, password: String) {
        guard isAllowedServer(serverURL) else {
            showQRCodeForOtherServerAlert()
            return
        }

        NCSettingsController.sharedInstance().addNewAccount(forUser: user, withToken: password, inServer: serverURL)
        delegate?.loginViewControllerDidFinish()
    }

    func qrScanner(_ scanner: QRScannerViewController, didScanNextcloudOnetimeLogin serverURL: String, user: String, onetimeToken: String) {
        guard isAllowedServer(serverURL) else {
            showQRCodeForOtherServerAlert()
            return
        }

        loginWithOnetimeToken(serverURL: serverURL, user: user, onetimeToken: onetimeToken)
    }

    private func loginWithOnetimeToken(serverURL: String, user: String, onetimeToken: String) {
        NotificationPresenter.shared().present(text: NSLocalizedString("Trying to login…", comment: "Waiting message when trying to login with QR code"))
        NotificationPresenter.shared().displayActivityIndicator(true)

        // Checked first, because a failed token exchange can't tell an untrusted certificate apart from a used token
        NCAPIController.sharedInstance().getServerCapabilities(forServer: serverURL) { [weak self] _, error in
            guard let self else { return }

            if let error, error.underlyingError.code == NSURLErrorServerCertificateUntrusted {
                NotificationPresenter.shared().dismiss()
                self.pendingOnetimeLogin = OnetimeLogin(serverURL: serverURL, user: user, onetimeToken: onetimeToken)

                DispatchQueue.main.async {
                    NCCertificate.shared.presentViewControllerCertificate(withError: error.underlyingError, viewController: self, delegate: self)
                }

                return
            }

            // We received a onetime login token and need to convert it to a permanent one. The token only allows to retrieve a permanent one, no other routes allowed
            NCAPIController.sharedInstance().getAppPassword(forServer: serverURL, withUsername: user, andPassword: onetimeToken, isOnetimeToken: true) { [weak self] permanentAppToken in
                NotificationPresenter.shared().dismiss()

                guard let permanentAppToken else {
                    self?.showAlert(
                        title: NSLocalizedString("Could not login with QR code", comment: ""),
                        message: NSLocalizedString("The token might be used already or is expired. Please generate a new QR code and retry.", comment: ""))

                    return
                }

                NCSettingsController.sharedInstance().addNewAccount(forUser: user, withToken: permanentAppToken, inServer: serverURL)
                self?.delegate?.loginViewControllerDidFinish()
            }
        }
    }
}
