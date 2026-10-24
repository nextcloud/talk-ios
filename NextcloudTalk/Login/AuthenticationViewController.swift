//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import WebKit

protocol AuthenticationViewControllerDelegate: AnyObject {
    func authenticationViewControllerDidFinish(_ viewController: AuthenticationViewController)
}

class AuthenticationViewController: UIViewController, WKNavigationDelegate {

    private static let authTokenFlowEndpoint = "/index.php/login/flow"

    weak var delegate: AuthenticationViewControllerDelegate?
    var serverUrl: String
    var user: String?

    private var webView: WKWebView?
    private var activityIndicatorView: UIActivityIndicatorView?

    init(serverUrl: String) {
        self.serverUrl = serverUrl
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        var urlString = "\(serverUrl)\(AuthenticationViewController.authTokenFlowEndpoint)"

        if let user {
            urlString = "\(urlString)?user=\(user)"
        }

        guard let url = URL(string: urlString) else {
            NSLog("Invalid login flow URL: %@", urlString)
            return
        }

        let storage = HTTPCookieStorage.shared
        storage.cookies?.forEach { storage.deleteCookie($0) }

        let websiteDataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: websiteDataTypes, modifiedSince: Date(timeIntervalSince1970: 0)) {
            var request = URLRequest(url: url)
            request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")

            let webView = DebounceWebView(frame: self.view.frame, configuration: configuration)
            webView.customUserAgent = NCAppBranding.userAgentForLogin()
            webView.navigationDelegate = self
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView.load(request)
            self.view.addSubview(webView)
            self.webView = webView

            let activityIndicatorView = UIActivityIndicatorView()
            activityIndicatorView.center = self.view.center
            activityIndicatorView.color = NCAppBranding.brandColor()
            activityIndicatorView.startAnimating()
            self.view.addSubview(activityIndicatorView)
            self.activityIndicatorView = activityIndicatorView
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.view.backgroundColor = NCAppBranding.themeColor()

        NCAppBranding.styleViewController(self)

        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonPressed))
        cancelButton.accessibilityHint = NSLocalizedString("Double tap to dismiss authentication dialog", comment: "")
        self.navigationController?.navigationBar.topItem?.leftBarButtonItem = cancelButton
    }

    @objc func cancelButtonPressed() {
        self.dismiss(animated: true)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return NCAppBranding.statusBarStyleForBrandColor()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    // MARK: - WKWebView Navigation Delegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if url.scheme == "nc" {
            var user: String?
            var token: String?
            let userPrefix = "user:"
            let passPrefix = "password:"

            for component in url.absoluteString.components(separatedBy: "&") {
                if component.hasPrefix(userPrefix) {
                    user = component.dropFirst(userPrefix.count).replacingOccurrences(of: "+", with: " ").removingPercentEncoding
                }

                if component.hasPrefix(passPrefix) {
                    token = component.dropFirst(passPrefix.count).replacingOccurrences(of: "+", with: " ").removingPercentEncoding
                }
            }

            NCSettingsController.sharedInstance().addNewAccount(forUser: user ?? "", withToken: token ?? "", inServer: serverUrl)
            self.delegate?.authenticationViewControllerDidFinish(self)
            decisionHandler(.cancel)
            return
        }

        if navigationAction.targetFrame == nil {
            NCUtils.openLinkInBrowser(link: url.absoluteString)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if CCCertificate.sharedManager().checkTrustedChallenge(challenge), let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // Set a different accessibility identifier, to correctly determine if the webview is interactive or not
        webView.accessibilityIdentifier = "nonInteractiveWebLoginView"

        // Disable user interaction to prevent any unwanted zooming while the navigation is ongoing
        webView.isUserInteractionEnabled = false

        activityIndicatorView?.stopAnimating()
        activityIndicatorView?.removeFromSuperview()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.isUserInteractionEnabled = true
        webView.accessibilityIdentifier = "interactiveWebLoginView"
    }
}
