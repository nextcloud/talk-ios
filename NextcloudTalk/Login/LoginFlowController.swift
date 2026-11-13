//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AuthenticationServices
import os
import UIKit

// TEMP CI debugging
let loginDebugLog = Logger(subsystem: "com.nextcloud.Talk", category: "LoginDebug")

private func startMainQueueHeartbeat(remaining: Int = 180) {
    guard remaining > 0 else { return }
    loginDebugLog.error("main queue alive")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { startMainQueueHeartbeat(remaining: remaining - 1) }
}

/// Logs in with login flow v2, showing the server's login page in an authentication session
@MainActor
class LoginFlowController: NSObject, ASWebAuthenticationPresentationContextProviding {

    enum Outcome {
        case loggedIn
        case cancelled
        case failed
    }

    private let serverUrl: String
    private let user: String?
    private weak var presentingViewController: UIViewController?
    private var completion: ((Outcome) -> Void)?

    private var loginTask: Task<Void, Never>?
    private var authSession: ASWebAuthenticationSession?

    init(serverUrl: String, user: String?, presentingViewController: UIViewController, completion: @escaping (Outcome) -> Void) {
        self.serverUrl = serverUrl
        self.user = user
        self.presentingViewController = presentingViewController
        self.completion = completion
    }

    func start() {
        startMainQueueHeartbeat()
        loginTask = Task { [weak self] in
            await self?.login()
        }
    }

    private func login() async {
        guard let flow = await NCAPIController.shared.startLoginFlowV2(forServer: serverUrl) else {
            finish(.failed)
            return
        }

        var loginUrl = flow.login
        if let user {
            loginUrl.append(queryItems: [URLQueryItem(name: "user", value: user)])
        }

        // The login flow never redirects back to the app, so this is only called when the user closes the session
        let authSession = ASWebAuthenticationSession(url: loginUrl, callbackURLScheme: nil) { [weak self] _, _ in
            self?.finish(.cancelled)
        }

        authSession.presentationContextProvider = self
        authSession.prefersEphemeralWebBrowserSession = true
        self.authSession = authSession

        guard authSession.start() else {
            finish(.failed)
            return
        }

        while !Task.isCancelled {
            loginDebugLog.error("poll start")
            if let credentials = await NCAPIController.shared.pollLoginFlowV2(withToken: flow.token, atEndpoint: flow.endpoint) {
                loginDebugLog.error("poll got credentials")
                guard !Task.isCancelled else { return }

                NCSettingsController.sharedInstance().addNewAccount(forUser: credentials.loginName, withToken: credentials.appPassword, inServer: serverUrl)
                loginDebugLog.error("account added")
                finish(.loggedIn)
                return
            }

            loginDebugLog.error("poll no credentials")
            try? await Task.sleep(for: .seconds(1))
        }
        loginDebugLog.error("poll loop cancelled")
    }

    private func finish(_ outcome: Outcome) {
        loginDebugLog.error("finish \(String(describing: outcome), privacy: .public)")
        // Closing the session calls its completion handler again
        guard let completion else { return }
        self.completion = nil

        loginTask?.cancel()

        // After logging in the login screen is dismissed together with the session, a separate dismissal can block it
        if outcome != .loggedIn {
            authSession?.cancel()
            authSession = nil
        }

        completion(outcome)
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return presentingViewController?.view.window ?? ASPresentationAnchor()
    }
}
