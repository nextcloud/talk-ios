//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objcMembers class MessageTranslationViewController: UIViewController {

    @IBOutlet weak var fromLabel: UILabel!
    @IBOutlet weak var fromButton: UIButton!
    @IBOutlet weak var toButton: UIButton!
    @IBOutlet weak var toLabel: UILabel!
    @IBOutlet weak var textViewsContainerView: UIView!
    @IBOutlet weak var originalTextView: UITextView!
    @IBOutlet weak var originalTextViewHeight: NSLayoutConstraint!
    @IBOutlet weak var translateTextView: UITextView!
    @IBOutlet weak var buttonsContainerView: UIView!
    @IBOutlet weak var buttonsContainerViewHeight: NSLayoutConstraint!

    var originalMessage: String?
    var availableTranslations: [NCTranslation]?
    var userLanguageCode: String?
    var activeAccount: TalkAccount?

    let textHorizontalPadding = 12.0
    let textVerticalPadding = 10.0
    let textContainerPadding = 16.0

    var translatedText: String = ""
    var detectedFromLanguageCode: String = ""
    var selectedFromLanguageCode: String = ""
    var selectedToLanguageCode: String = ""
    var translationErrorMessage: String = ""
    var modifyingProfileView = UIActivityIndicatorView()
    var didTriggerInitialTranslation: Bool = false

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    init(message: String, availableTranslations: [NCTranslation]) {
        super.init(nibName: "MessageTranslationViewController", bundle: .main)
        self.originalMessage = message
        self.availableTranslations = availableTranslations
        self.userLanguageCode = Locale.current.languageCode
        self.activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Translation", comment: "")

        self.fromLabel.text = (NSLocalizedString("From", comment: "'From' which language user wants to translate text") + ":")
        self.toLabel.text = (NSLocalizedString("To", comment: "'To' which language user wants to translate text") + ":")

        self.originalTextView.text = originalMessage

        self.originalTextView.textContainerInset = UIEdgeInsets(top: textVerticalPadding, left: textHorizontalPadding,
                                                                bottom: textVerticalPadding, right: textHorizontalPadding)
        self.translateTextView.textContainerInset = UIEdgeInsets(top: textVerticalPadding, left: textHorizontalPadding,
                                                                 bottom: textVerticalPadding, right: textHorizontalPadding)
        self.originalTextView.textContainer.lineFragmentPadding = 0
        self.translateTextView.textContainer.lineFragmentPadding = 0
        self.originalTextView.layer.cornerRadius = 8
        self.translateTextView.layer.cornerRadius = 8

        self.modifyingProfileView = UIActivityIndicatorView()
        self.modifyingProfileView.color = NCAppBranding.themeTextColor()

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
        if #unavailable(iOS 26.0) {
            self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        if !didTriggerInitialTranslation {
            self.setTranslatingUI()
            self.didTriggerInitialTranslation = true
            self.configureFromButton(title: NSLocalizedString("Detecting language", comment: ""), enabled: false)
            self.configureToButton(title: initialToLanguage(), enabled: false, fromLanguageCode: "")
            self.adjustOriginalTextViewSizeToViewSize(size: self.view.bounds.size)

            if NCDatabaseManager.sharedInstance().hasTranslationProviders(forAccountId: activeAccount?.accountId ?? "") {
                NCAPIController.sharedInstance().getAvailableTranslations(for: activeAccount) { languages, languageDetection, error, _ in
                    if let translations = languages as? [NCTranslation], error == nil {
                        self.availableTranslations = translations
                        if languageDetection {
                            self.translateOriginalText(from: "", to: self.userLanguageCode ?? "")
                        } else {
                            self.configureFromButton(title: nil, enabled: true)
                            self.configureToButton(title: nil, enabled: false, fromLanguageCode: "")
                            self.removeTranslatingUI()
                        }
                    } else {
                        self.showTranslationError(message: NSLocalizedString("Could not get available languages", comment: ""))
                        self.removeTranslatingUI()
                    }
                }
            } else {
                self.translateOriginalText(from: "", to: userLanguageCode ?? "")
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { _ in
            self.adjustOriginalTextViewSizeToViewSize(size: self.view.bounds.size)
        }
    }

    func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    func adjustOriginalTextViewSizeToViewSize(size: CGSize) {
        let font = originalTextView.font ?? UIFont.systemFont(ofSize: 16)
        let height = (originalMessage?.height(withConstrainedWidth: size.width - textContainerPadding * 2 - textHorizontalPadding * 2, font: font) ?? 0) + textVerticalPadding * 2
        let maxHeight = (size.height - textViewsContainerView.frame.origin.y) / 2.0 - (textVerticalPadding * 2)

        self.originalTextViewHeight.constant = min(height, maxHeight)
    }

    func initialToLanguage() -> String {
        let availableToLanguage = Locale.current.localizedString(forLanguageCode: userLanguageCode ?? "") ?? ""
        guard let availableTranslations = availableTranslations else { return availableToLanguage }
        for availableTranslation in availableTranslations where availableTranslation.to == userLanguageCode {
            return availableTranslation.toLabel
        }
        return availableToLanguage
    }

    // MARK: - Available Languages

    func availableFromLanguagesLabels() -> [String] {
        var availableFromLanguages: [String] = []
        guard let availableTranslations = availableTranslations else { return availableFromLanguages }
        for availableTranslation in availableTranslations where !availableFromLanguages.contains(availableTranslation.fromLabel) {
            availableFromLanguages.append(availableTranslation.fromLabel)
        }
        return availableFromLanguages
    }

    func fromLanguageLabel(languageCode: String) -> String {
        let fromLanguageLabel: String = ""
        guard let availableTranslations = availableTranslations else { return fromLanguageLabel }
        for availableTranslation in availableTranslations where availableTranslation.from == languageCode {
            return availableTranslation.fromLabel
        }
        return fromLanguageLabel
    }

    func fromLanguageCode(languageLabel: String) -> String {
        let fromLanguageCode: String = ""
        guard let availableTranslations = availableTranslations else { return fromLanguageCode }
        for availableTranslation in availableTranslations where availableTranslation.fromLabel == languageLabel {
            return availableTranslation.from
        }
        return fromLanguageCode
    }

    func availableToLanguagesLabels(fromLanguageCode: String) -> [String] {
        var availableToLanguages: [String] = []
        guard let availableTranslations = availableTranslations else { return availableToLanguages }
        for availableTranslation in availableTranslations where
        availableTranslation.from == fromLanguageCode && !availableToLanguages.contains(availableTranslation.toLabel) {
            availableToLanguages.append(availableTranslation.toLabel)
        }
        return availableToLanguages
    }

    func toLanguageLabel(languageCode: String) -> String {
        let toLanguageLabel: String = ""
        guard let availableTranslations = availableTranslations else { return toLanguageLabel }
        for availableTranslation in availableTranslations where availableTranslation.to == languageCode {
            return availableTranslation.toLabel
        }
        return toLanguageLabel
    }

    func toLanguageCode(languageLabel: String) -> String {
        let toLanguageCode: String = ""
        guard let availableTranslations = availableTranslations else { return toLanguageCode }
        for availableTranslation in availableTranslations where availableTranslation.toLabel == languageLabel {
            return availableTranslation.to
        }
        return toLanguageCode
    }

    // MARK: - Translate

    func translateOriginalText(from: String, to: String) {
        self.setTranslatingUI()
        NCAPIController.sharedInstance().translateMessage(originalMessage, from: from, to: to, for: activeAccount) { responseDict, error, _ in
            self.removeTranslatingUI()

            if let responseDict = responseDict as? [String: String] {
                if let translatedText = responseDict["text"] {
                    self.translatedText = translatedText
                    self.translateTextView.text = translatedText
                }
                if let translatedFrom = responseDict["from"] {
                    self.detectedFromLanguageCode = translatedFrom
                    self.selectedToLanguageCode = translatedFrom
                    let detectedText = from.isEmpty ? " (" + NSLocalizedString("detected", comment: "") + ")" : ""
                    let title = self.fromLanguageLabel(languageCode: translatedFrom) + detectedText
                    self.configureFromButton(title: title, enabled: !from.isEmpty)
                    self.configureToButton(title: self.toButton.titleLabel?.text, enabled: true, fromLanguageCode: translatedFrom)
                }
                if let errorMessage = responseDict["message"] {
                    self.translationErrorMessage = errorMessage
                }
            }

            if error != nil {
                if self.detectedFromLanguageCode.isEmpty {
                    self.configureFromButton(title: nil, enabled: true)
                    self.configureToButton(title: nil, enabled: false, fromLanguageCode: "")
                }
                var errorMessage = NSLocalizedString("An error occurred trying to translate message", comment: "")
                if !self.translationErrorMessage.isEmpty {
                    errorMessage = self.translationErrorMessage
                }
                self.showTranslationError(message: errorMessage)
            }
        }
    }

    // MARK: - User Interface

    func setTranslatingUI() {
        self.translateTextView.text = ""
        self.modifyingProfileView.startAnimating()
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: modifyingProfileView)
    }

    func removeTranslatingUI() {
        self.modifyingProfileView.stopAnimating()
        self.navigationItem.rightBarButtonItem = nil
    }

    func configureFromButton(title: String?, enabled: Bool) {
        let title = title ?? NSLocalizedString("Select language", comment: "")
        self.fromButton.setTitle(title, for: .normal)
        var actions: [UIAction] = []
        for languageLabel in availableFromLanguagesLabels() {
            actions.append(UIAction(title: languageLabel, image: nil, handler: { _ in
                self.fromLanguageLabelSelected(languageLabel: languageLabel)
            }))
        }
        self.fromButton.menu = UIMenu(title: "", image: nil, identifier: nil, options: [], children: actions)
        self.fromButton.showsMenuAsPrimaryAction = true
        self.fromButton.isEnabled = enabled
    }

    func fromLanguageLabelSelected(languageLabel: String) {
        let fromLanguageCode = fromLanguageCode(languageLabel: languageLabel)
        self.selectedFromLanguageCode = fromLanguageCode
        self.fromButton.setTitle(languageLabel, for: .normal)
        self.configureToButton(title: nil, enabled: true, fromLanguageCode: fromLanguageCode)
    }

    func configureToButton(title: String?, enabled: Bool, fromLanguageCode: String) {
        let title = title ?? NSLocalizedString("Select language", comment: "")
        self.toButton.setTitle(title, for: .normal)
        var actions: [UIAction] = []
        for languageLabel in availableToLanguagesLabels(fromLanguageCode: fromLanguageCode) {
            actions.append(UIAction(title: languageLabel, image: nil, handler: { _ in
                self.toLanguageLabelSelected(languageLabel: languageLabel)
            }))
        }
        self.toButton.menu = UIMenu(title: "", image: nil, identifier: nil, options: [], children: actions)
        self.toButton.showsMenuAsPrimaryAction = true
        self.toButton.isEnabled = enabled
    }

    func toLanguageLabelSelected(languageLabel: String) {
        let toLanguageCode = toLanguageCode(languageLabel: languageLabel)
        self.selectedToLanguageCode = toLanguageCode
        self.toButton.setTitle(languageLabel, for: .normal)
        self.translateOriginalText(from: selectedFromLanguageCode, to: selectedToLanguageCode)
    }

    func showTranslationError(message: String) {
        let errorDialog = UIAlertController(title: NSLocalizedString("Translation failed", comment: ""), message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default)
        errorDialog.addAction(okAction)
        self.present(errorDialog, animated: true, completion: nil)
    }
}
