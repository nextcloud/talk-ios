//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import WebRTC

protocol CallDebugControllerDelegate: AnyObject {
    // Simulcast qualities and remote video blocking need to be applied again
    func callDebugControllerDidChangeOverrides(_ controller: CallDebugController)

    func callDebugControllerDidUpdateConnectionStats(_ controller: CallDebugController)

    // Describes the call view, the call controller adds the details of the connections
    func debugInfoLines(for controller: CallDebugController) -> [String]

    func callDebugController(_ controller: CallDebugController, present viewController: UIViewController)
}

// Debug menu of the call view, only offered in test environments and only accessed on the main queue
final class CallDebugController {

    typealias PeerIdentifier = String

    weak var delegate: CallDebugControllerDelegate?

    var callController: NCCallController?

    private(set) var simulcastQualityOverride: SimulcastVideoQuality?
    private(set) var remoteVideoBlockedOverride: Bool?

    private let peerStore: CallPeerStore
    private var connectionStatsTimer: Timer?
    private var connectionStatsReports: [PeerIdentifier: RTCStatisticsReport] = [:]
    private var connectionStatsTexts: [PeerIdentifier: String] = [:]

    init(peerStore: CallPeerStore) {
        self.peerStore = peerStore
    }

    deinit {
        connectionStatsTimer?.invalidate()
    }

    func connectionStatsText(forPeerIdentifier peerIdentifier: String) -> String? {
        return connectionStatsTexts[peerIdentifier]
    }

    func menu() -> UIMenu {
        let qualityOptions: [(String, SimulcastVideoQuality?)] = [("Automatic", nil), ("Low", .low), ("Medium", .medium), ("High", .high)]
        let qualityActions = qualityOptions.map { title, quality in
            let action = UIAction(title: title) { [unowned self] _ in
                self.simulcastQualityOverride = quality
                self.delegate?.callDebugControllerDidChangeOverrides(self)
            }
            action.state = quality == simulcastQualityOverride ? .on : .off
            return action
        }

        let blockingOptions: [(String, Bool?)] = [("Automatic", nil), ("Block all", true), ("Block none", false)]
        let blockingActions = blockingOptions.map { title, blocked in
            let action = UIAction(title: title) { [unowned self] _ in
                self.remoteVideoBlockedOverride = blocked
                self.delegate?.callDebugControllerDidChangeOverrides(self)
            }
            action.state = blocked == remoteVideoBlockedOverride ? .on : .off
            return action
        }

        let statsAction = UIAction(title: "Connection stats", image: .init(systemName: "chart.bar.xaxis")) { [unowned self] _ in
            self.setConnectionStatsVisible(self.connectionStatsTimer == nil)
        }
        statsAction.state = connectionStatsTimer != nil ? .on : .off

        let debugInfoAction = UIAction(title: "Show debug info", image: .init(systemName: "doc.text.magnifyingglass")) { [unowned self] _ in
            self.showDebugInfo()
        }

        var connectionActions: [UIMenuElement] = []

        // The ICE transport policy is set when a peer connection is created, so reconnect to apply it
        let relayOnlyAction = UIAction(title: "Relay only (TURN)", subtitle: "Reconnects the call") { [unowned self] _ in
            CallDebugSettings.relayOnlyIceCandidates.toggle()
            self.callController?.forceReconnect()
        }
        relayOnlyAction.state = CallDebugSettings.relayOnlyIceCandidates ? .on : .off
        connectionActions.append(relayOnlyAction)

        if callController?.usesExternalSignaling == true {
            connectionActions.append(UIAction(title: "Drop signaling connection", subtitle: "Like a network loss", attributes: .destructive) { [unowned self] _ in
                self.callController?.simulateSignalingConnectionLoss()
            })
        }

        connectionActions.append(UIAction(title: "Force reconnect", attributes: .destructive) { [unowned self] _ in
            self.callController?.forceReconnect()
        })

        return UIMenu(title: "Debug", image: .init(systemName: "ladybug"), children: [
            UIMenu(title: "", options: .displayInline, children: [statsAction, debugInfoAction]),
            UIMenu(title: "Connection", options: .displayInline, children: connectionActions),
            UIMenu(title: "Simulcast quality", subtitle: qualityOptions.first(where: { $0.1 == simulcastQualityOverride })?.0, image: .init(systemName: "square.3.layers.3d"), children: qualityActions),
            UIMenu(title: "Remote video", subtitle: blockingOptions.first(where: { $0.1 == remoteVideoBlockedOverride })?.0, image: .init(systemName: "video.slash"), children: blockingActions)
        ])
    }

    // MARK: - Connection stats

    func stopConnectionStats() {
        self.setConnectionStatsVisible(false)
    }

    private func setConnectionStatsVisible(_ visible: Bool) {
        connectionStatsTimer?.invalidate()
        connectionStatsTimer = nil
        connectionStatsReports = [:]
        connectionStatsTexts = [:]

        delegate?.callDebugControllerDidUpdateConnectionStats(self)

        guard visible else { return }

        connectionStatsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateConnectionStats()
        }

        self.updateConnectionStats()
    }

    private func updateConnectionStats() {
        let peers = peerStore.peers

        WebRTCCommon.shared.dispatch {
            CallDebugInfo.statistics(of: peers) { reports in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.connectionStatsTimer != nil else { return }

                    var newReports: [PeerIdentifier: RTCStatisticsReport] = [:]
                    var newTexts: [PeerIdentifier: String] = [:]

                    for peer in peers {
                        guard let report = reports[ObjectIdentifier(peer)] else { continue }

                        newReports[peer.peerIdentifier] = report
                        newTexts[peer.peerIdentifier] = CallStatsReport(report: report, previous: self.connectionStatsReports[peer.peerIdentifier]).tileSummary
                    }

                    self.connectionStatsReports = newReports
                    self.connectionStatsTexts = newTexts
                    self.delegate?.callDebugControllerDidUpdateConnectionStats(self)
                }
            }
        }
    }

    // MARK: - Debug info

    private func showDebugInfo() {
        guard let callController, let delegate else { return }

        var lines = delegate.debugInfoLines(for: self)
        lines.append("Debug overrides: simulcast \(simulcastQualityOverride.map { "\($0)" } ?? "automatic"), remote video blocked \(remoteVideoBlockedOverride.map { "\($0)" } ?? "automatic")")
        lines.append("")

        NotificationPresenter.shared().present(text: "Collecting debug info…", dismissAfterDelay: 1.0, includedStyle: .dark)

        callController.collectDebugInfo { [weak self] callInfo in
            guard let self else { return }

            lines.append(callInfo)
            let debugInfo = lines.joined(separator: "\n")

            let textViewController = MessageTextViewController(messageText: debugInfo)
            textViewController.loadViewIfNeeded()
            textViewController.messageTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            textViewController.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Copy", comment: ""), primaryAction: UIAction { _ in
                UIPasteboard.general.string = debugInfo
                NotificationPresenter.shared().present(text: "Debug info copied", dismissAfterDelay: 3.0, includedStyle: .dark)
            })

            self.delegate?.callDebugController(self, present: NCNavigationController(rootViewController: textViewController))
        }
    }
}
