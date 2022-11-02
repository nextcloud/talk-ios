//  Created by Marino Faggiana on 04/03/2019.
//  Copyright © 2019 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//  Author Marcel Müller <marcel-mueller@gmx.de>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import QRCodeReader

@objc public protocol QRCodeLoginControllerDelegate {
    @objc func readLoginDetails(serverUrl: String?, user: String?, password: String?)
}

@objc public class QRCodeLoginController: NSObject, QRCodeReaderViewControllerDelegate {

    lazy var reader: QRCodeReader = QRCodeReader()
    weak var delegate: UIViewController?

    lazy var readerVC: QRCodeReaderViewController = {
        let builder = QRCodeReaderViewControllerBuilder {
            $0.reader = QRCodeReader(metadataObjectTypes: [.qr], captureDevicePosition: .back)
            $0.showTorchButton = true
            $0.preferredStatusBarStyle = .lightContent
            $0.showOverlayView = true
            $0.rectOfInterest = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)

            $0.reader.stopScanningWhenCodeIsFound = false
        }

        return QRCodeReaderViewController(builder: builder)
    }()

    override init() {

    }

    @objc public init(delegate: UIViewController) {
        self.delegate = delegate
    }

    @objc func scan() {
        guard checkScanPermissions() else { return }

        readerVC.modalPresentationStyle = .formSheet
        readerVC.delegate = self

        readerVC.completionBlock = { (_: QRCodeReaderResult?) in
            self.readerVC.dismiss(animated: true, completion: nil)
        }

        delegate?.present(readerVC, animated: true, completion: nil)
    }

    private func checkScanPermissions() -> Bool {
        do {
            return try QRCodeReader.supportsMetadataObjectTypes()
        } catch let error as NSError {
            let alert: UIAlertController

            switch error.code {
            case -11852:
                alert = UIAlertController(
                    title: NSLocalizedString("Could not access camera", comment: ""),
                    message: NSLocalizedString("Camera access is not allowed. Check your settings.", comment: ""),
                    preferredStyle: .alert
                )

                alert.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: ""), style: .default, handler: { _ in
                    DispatchQueue.main.async {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
                        }
                    }
                }))

                alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil))
            default:
                alert = UIAlertController(
                    title: NSLocalizedString("Not supported", comment: ""),
                    message: NSLocalizedString("Scanning QR Codes is not supported on this device.", comment: ""),
                    preferredStyle: .alert
                )

                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
            }

            delegate?.present(alert, animated: true, completion: nil)

            return false
        }
    }

    public func reader(_ reader: QRCodeReaderViewController, didScanResult result: QRCodeReaderResult) {
        reader.stopScanning()

        if let urlComponents = NSURLComponents(string: result.value), var path = urlComponents.path, urlComponents.scheme == "nc", urlComponents.host == "login" {
            if path.starts(with: "/") {
                path.removeFirst()
            }

            if path.contains("user:") && path.contains("password:") && path.contains("server:") {
                let pathArray = path.components(separatedBy: "&")
                if pathArray.count == 3 {

                    let user = pathArray[0].replacingOccurrences(of: "user:", with: "")
                    let password = pathArray[1].replacingOccurrences(of: "password:", with: "")
                    let serverUrl = pathArray[2].replacingOccurrences(of: "server:", with: "")

                    (self.delegate as? QRCodeLoginControllerDelegate)?.readLoginDetails(serverUrl: serverUrl, user: user, password: password)
                    return
                }
            }
        }
    }

    public func readerDidCancel(_ reader: QRCodeReaderViewController) {
        reader.stopScanning()
    }
}
