//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import VisionKit

@objc protocol QRScannerViewControllerDelegate: AnyObject {
    func qrScanner(_ scanner: QRScannerViewController, didScanNextcloudLogin serverURL: String, user: String, password: String)
}

@objcMembers
class QRScannerViewController: UIViewController, DataScannerViewControllerDelegate {

    weak var delegate: QRScannerViewControllerDelegate?

    private var scannerViewController: DataScannerViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Setup scanner
        let scannerVC = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .accurate,
            isHighlightingEnabled: true
        )
        scannerVC.delegate = self
        scannerViewController = scannerVC

        // Embed scanner
        addChild(scannerVC)
        scannerVC.view.frame = view.bounds
        view.addSubview(scannerVC.view)
        scannerVC.didMove(toParent: self)

        // Instructions text view
        let instructionsTextView = UITextView()
        instructionsTextView.isEditable = false
        instructionsTextView.isSelectable = false
        instructionsTextView.isScrollEnabled = false
        instructionsTextView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        instructionsTextView.textColor = .white
        instructionsTextView.font = UIFont.systemFont(ofSize: 17)
        instructionsTextView.layer.cornerRadius = 8
        instructionsTextView.translatesAutoresizingMaskIntoConstraints = false
        let step1 = NSLocalizedString("1. Access your server in a web browser", comment: "First step in scanning QR code instructions")
        let step2 = NSLocalizedString("2. Go to Settings > Security > Create new app password", comment: "Second step in scanning QR code instructions")
        let step3 = NSLocalizedString("3. Scan the QR code shown there", comment: "Third step in scanning QR code instructions")
        instructionsTextView.text = String(format: "%@\n\n%@\n\n%@", step1, step2, step3)
        instructionsTextView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        instructionsTextView.textContainer.lineFragmentPadding = 0
        view.addSubview(instructionsTextView)

        NSLayoutConstraint.activate([
            instructionsTextView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            instructionsTextView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            instructionsTextView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionsTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        // Close button
        let closeButton = UIButton(type: .roundedRect)
        closeButton.setTitle(NSLocalizedString("Close", comment: ""), for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        closeButton.layer.cornerRadius = 8
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeButtonPressed), for: .touchUpInside)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard DataScannerViewController.isAvailable else {
            showCameraPermissionAlert()
            return
        }

        try? scannerViewController?.startScanning()
    }

    // MARK: - Utils

    class func isDataScannerAvailable() -> Bool {
        return DataScannerViewController.isAvailable
    }

    class func isDataScannerSupported() -> Bool {
        return DataScannerViewController.isSupported
    }

    // MARK: - Close Button Action

    @objc private func closeButtonPressed() {
        dismiss(animated: true)
    }

    // MARK: - Camera access alert

    private func showCameraPermissionAlert() {
        let alert = UIAlertController(
            title: NSLocalizedString("Could not access camera", comment: ""),
            message: NSLocalizedString("Camera access is not allowed. Check your settings.", comment: ""),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: ""), style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })

        present(alert, animated: true)
    }

    // MARK: - DataScannerViewController delegate

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        if let item = addedItems.first {
            handleScan(item)
        }
    }

    private func handleScan(_ item: RecognizedItem) {
        guard case let .barcode(barcode) = item,
              let value = barcode.payloadStringValue else { return }

        if let urlComponents = NSURLComponents(string: value), var path = urlComponents.path, urlComponents.scheme == "nc", urlComponents.host == "login" {
            if path.starts(with: "/") {
                path.removeFirst()
            }

            if path.contains("user:") && path.contains("password:") && path.contains("server:") {
                let pathArray = path.components(separatedBy: "&")
                if pathArray.count == 3 {

                    let user = pathArray[0].replacingOccurrences(of: "user:", with: "")
                    let password = pathArray[1].replacingOccurrences(of: "password:", with: "")
                    let serverUrl = pathArray[2].replacingOccurrences(of: "server:", with: "")

                    scannerViewController?.stopScanning()
                    self.dismiss(animated: true)
                    self.delegate?.qrScanner(self, didScanNextcloudLogin: serverUrl, user: user, password: password)

                    return
                }
            }
        }
    }

    func dataScannerDidTapToDismiss(_ dataScanner: DataScannerViewController) {
        closeButtonPressed()
    }
}
