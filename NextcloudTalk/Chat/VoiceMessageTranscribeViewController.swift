//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import Speech

class VoiceMessageTranscribeViewController: UIViewController {

    @IBOutlet weak var transcribeTextView: UITextView!

    private let audioFileUrl: URL
    private let activityIndicator = UIActivityIndicatorView()
    private let supportedLocales = ["de", "it", "en", "fr", "es"]

    init(audiofileUrl audioFileUrl: URL) {
        self.audioFileUrl = audioFileUrl

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Transcript", comment: "TRANSLATORS transcript of a voice-message")

        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(closeViewController))
        self.navigationController?.navigationBar.topItem?.leftBarButtonItem = cancelButton

        if #available(iOS 26.0, *) {
            self.activityIndicator.color = .label
        } else {
            self.activityIndicator.color = NCAppBranding.themeTextColor()
        }

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: self.activityIndicator)

        self.activityIndicator.startAnimating()

        self.checkPermissionAndStartTranscription()
    }

    @objc func closeViewController() {
        self.dismiss(animated: true)
    }

    private func checkPermissionAndStartTranscription() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                guard status == .authorized else {
                    self.showSpeechRecognitionNotAvailable()

                    return
                }

                self.showLocaleSelection()
            }
        }
    }

    private func showLocaleSelection() {
        let optionsActionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        // Use current locale for showing localized language names
        let currentLocale = Locale.current

        for localeString in self.supportedLocales {
            let speechLocale = Locale(identifier: localeString)
            let speechRecognizer = SFSpeechRecognizer(locale: speechLocale)

            // We explicitly want to use on-device recognition
            guard let speechRecognizer, speechRecognizer.isAvailable, speechRecognizer.supportsOnDeviceRecognition else { continue }

            optionsActionSheet.addAction(UIAlertAction(title: currentLocale.localizedString(forLanguageCode: localeString), style: .default) { [weak self] _ in
                self?.transcribe(with: speechLocale)
            })
        }

        optionsActionSheet.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { [weak self] _ in
            self?.closeViewController()
        })

        self.present(optionsActionSheet, animated: true)
    }

    private func transcribe(with locale: Locale) {
        let speechRecognizer = SFSpeechRecognizer(locale: locale)
        let speechRecognitionRequest = SFSpeechURLRecognitionRequest(url: self.audioFileUrl)
        speechRecognitionRequest.requiresOnDeviceRecognition = true
        speechRecognitionRequest.shouldReportPartialResults = true

        speechRecognizer?.recognitionTask(with: speechRecognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let error {
                NSLog("Recognition task failed: %@", (error as NSError).description)
                self.showSpeechRecognitionError(error.localizedDescription)

                return
            }

            self.setTranscribedText(result?.bestTranscription.formattedString, isFinal: result?.isFinal ?? false)
        }
    }

    private func showSpeechRecognitionError(_ errorDescription: String) {
        let alert = UIAlertController(title: NSLocalizedString("Speech recognition failed", comment: ""),
                                      message: errorDescription,
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { [weak self] _ in
            self?.closeViewController()
        })

        self.present(alert, animated: true)
    }

    private func showSpeechRecognitionNotAvailable() {
        let alert = UIAlertController(title: NSLocalizedString("Could not access speech recognition", comment: ""),
                                      message: NSLocalizedString("Speech recognition access is not allowed. Check your settings.", comment: ""),
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: ""), style: .default) { [weak self] _ in
            self?.closeViewController()

            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        })

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel) { [weak self] _ in
            self?.closeViewController()
        })

        self.present(alert, animated: true)
    }

    private func setTranscribedText(_ text: String?, isFinal: Bool) {
        self.transcribeTextView.text = text

        if isFinal {
            self.activityIndicator.stopAnimating()
            self.activityIndicator.removeFromSuperview()
        }
    }
}
