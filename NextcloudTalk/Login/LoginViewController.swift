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
class LoginViewController: UIViewController, UITextFieldDelegate, CCCertificateDelegate, DetailedOptionsSelectorTableViewControllerDelegate, AuthenticationViewControllerDelegate, QRScannerViewControllerDelegate {

    weak var delegate: LoginViewControllerDelegate?

    var authenticationViewController = AuthenticationViewController()
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

    func trustedCerticateAccepted() {
        loginButtonPressed(self)
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

        // Start animating activity indicator
        activityIndicatorView.startAnimating()
        activityIndicatorView.isHidden = false

        // Check if valid Nextcloud server
        NCAPIController.sharedInstance().getServerCapabilities(forServer: normalizedServerURL) { serverCapabilities, error in
            self.activityIndicatorView.stopAnimating()
            self.activityIndicatorView.isHidden = true

            if let error = error as? NSError {
                if error.code == NSURLErrorServerCertificateUntrusted {
                    DispatchQueue.main.async {
                        CCCertificate.sharedManager()
                            .presentViewControllerCertificate(
                                withTitle: error.localizedDescription,
                                viewController: self,
                                delegate: self)
                    }
                } else {
                    self.showServerNotFoundAlert(withError: error.localizedDescription)
                }
            } else {
                if let serverCapabilities = serverCapabilities as? [String: Any] {
                    if let capabilities = serverCapabilities["capabilities"] as? [String: Any],
                       let talk = capabilities["spreed"] as? [String: Any],
                       let features = talk["features"] as? [String] {
                        if features.contains(kMinimumRequiredTalkCapability) {
                            self.presentAuthenticationViewController(serverURL: normalizedServerURL, user: nil)
                        } else if features.isEmpty {
                            self.showAlert(
                                title: String(format: NSLocalizedString("%@ not installed", comment: "{app name} is not installed"), talkAppName),
                                message: String(format: NSLocalizedString("It seems that %@ is not installed in your server.", comment: "It seems that {app name} is not installed in your server."), talkAppName))
                        } else {
                            self.showAlert(
                                title: String(format: NSLocalizedString("%@ version not supported", comment: "{app name} version not supported"), talkAppName),
                                message: String(format: NSLocalizedString("Please update your server with the latest %@ version available.", comment: "Please update your server with the latest {app name} version available."), talkAppName))
                        }
                    }
                } else {
                    self.showServerNotFoundAlert(withError: nil)
                }
            }
        }
    }

    func presentAuthenticationViewController(serverURL: String, user: String?) {
        guard let authenticationVC = AuthenticationViewController(serverUrl: serverURL) else { return }

        authenticationViewController = authenticationVC
        authenticationViewController.delegate = self

        if user != nil {
            authenticationViewController.user = user
        }

        let authenticationNC = UINavigationController(rootViewController: authenticationViewController)
        present(authenticationNC, animated: true)
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
            if !accountAlreadyIncluded {
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

        if let accountSelectorVC = DetailedOptionsSelectorTableViewController(accounts: importedAccounts, andStyle: .insetGrouped) {
            accountSelectorVC.title = NSLocalizedString("Import account", comment: "")
            accountSelectorVC.delegate = self
            let accountSelectorNC = NCNavigationController(rootViewController: accountSelectorVC)
            self.present(accountSelectorNC, animated: true)
        }
    }

    // MARK: - DetailedOptionSelector delegate

    func detailedOptionsSelector(_ viewController: DetailedOptionsSelectorTableViewController!, didSelectOptionWithIdentifier option: DetailedOption!) {
        dismiss(animated: true) {
            self.presentAuthenticationViewController(serverURL: option.subtitle, user: option.identifier)
        }
    }

    func detailedOptionsSelectorWasCancelled(_ viewController: DetailedOptionsSelectorTableViewController!) {
        dismiss(animated: true)
    }

    // MARK: - Alerts

    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: {[weak self] _ in
            self?.serverTextField.becomeFirstResponder()
        }))
        self.present(alert, animated: true)
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

    // MARK: - AuthenticationViewController delegate

    func authenticationViewControllerDidFinish(_ viewController: AuthenticationViewController!) {
        if viewController == authenticationViewController {
            delegate?.loginViewControllerDidFinish()
        }
    }

    // MARK: - QRScannerViewControllerDelegate

    func qrScanner(_ scanner: QRScannerViewController, didScanNextcloudLogin serverURL: String, user: String, password: String) {
        NCSettingsController.sharedInstance().addNewAccount(forUser: user, withToken: password, inServer: serverURL)
        delegate?.loginViewControllerDidFinish()
    }

    func qrScanner(_ scanner: QRScannerViewController, didScanNextcloudOnetimeLogin serverURL: String, user: String, onetimeToken: String) {
        // We received a onetime login token and need to convert it to a permanent one. The token only allows to retrieve a permanent one, no other routes allowed
        NCAPIController.sharedInstance().getAppPasswordOnetime(forServer: serverURL, withUsername: user, andOnetimeToken: onetimeToken) { [weak self] permanentAppToken in
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
