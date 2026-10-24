//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import WebRTC

// Switches of the call debug menu, kept for the lifetime of the app
enum CallDebugSettings {
    // Only applies to peer connections created afterwards
    static var relayOnlyIceCandidates = false
}

enum CallDebugInfo {

    static func statistics(of peers: [NCPeerConnection], completion: @escaping ([ObjectIdentifier: RTCStatisticsReport]) -> Void) {
        WebRTCCommon.shared.assertQueue()

        let group = DispatchGroup()
        var reports = [ObjectIdentifier: RTCStatisticsReport]()

        for peer in peers {
            guard let peerConnection = peer.getPeerConnection() else { continue }

            group.enter()
            peerConnection.statistics { report in
                WebRTCCommon.shared.dispatch {
                    reports[ObjectIdentifier(peer)] = report
                    group.leave()
                }
            }
        }

        group.notify(queue: .global()) {
            WebRTCCommon.shared.dispatch {
                completion(reports)
            }
        }
    }

    // Bitrates and recent packet loss are only known from the difference of two reports
    static func sampleStatistics(of peers: [NCPeerConnection], completion: @escaping ([ObjectIdentifier: CallStatsReport]) -> Void) {
        statistics(of: peers) { firstReports in
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                WebRTCCommon.shared.dispatch {
                    CallDebugInfo.statistics(of: peers) { secondReports in
                        var reports = [ObjectIdentifier: CallStatsReport]()

                        for (key, report) in secondReports {
                            reports[key] = CallStatsReport(report: report, previous: firstReports[key])
                        }

                        completion(reports)
                    }
                }
            }
        }
    }
}

struct CallStatsReport {

    let report: RTCStatisticsReport
    let previous: RTCStatisticsReport?

    // MARK: - Summaries

    var tileSummary: String {
        var lines = [String]()

        if let video = inboundRtp(kind: "video"), let width = video.int("frameWidth"), let height = video.int("frameHeight") {
            var parts = ["\(width)x\(height)"]
            parts.appendIfPresent(video.int("framesPerSecond").map { "\($0) fps" })
            parts.appendIfPresent(codecName(of: video))

            if let freezes = video.int("freezeCount"), freezes > 0 {
                parts.append("\(freezes) freezes")
            }

            lines.append(parts.joined(separator: " · "))
            lines.append(receiveQuality(of: video).joined(separator: " · "))
        } else if let audio = inboundRtp(kind: "audio") {
            lines.append((["audio"] + receiveQuality(of: audio)).joined(separator: " · "))
        }

        if let connection = selectedConnectionSummary {
            lines.append(connection)
        }

        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var detailedLines: [String] {
        var lines = [String]()

        lines.append("Connection: " + (selectedConnectionSummary ?? "no selected candidate pair"))

        if let candidatePair = selectedCandidatePair, let outgoingBitrate = candidatePair.double("availableOutgoingBitrate") {
            lines.append("Outgoing estimate: \(Int(outgoingBitrate / 1000)) kbps")
        }

        for kind in ["audio", "video"] {
            for inbound in stats(ofType: "inbound-rtp") where inbound.string("kind") == kind {
                lines.append("\(kind.capitalized) in: " + inboundParts(of: inbound).joined(separator: ", "))
            }

            for outbound in stats(ofType: "outbound-rtp") where outbound.string("kind") == kind {
                let rid = outbound.string("rid").map { " [\($0)]" } ?? ""
                lines.append("\(kind.capitalized) out\(rid): " + outboundParts(of: outbound).joined(separator: ", "))
            }
        }

        return lines
    }

    // MARK: - Parts

    private func inboundParts(of inbound: RTCStatistics) -> [String] {
        var parts = [String]()

        if let width = inbound.int("frameWidth"), let height = inbound.int("frameHeight") {
            parts.append("\(width)x\(height)")
        }

        parts.appendIfPresent(inbound.int("framesPerSecond").map { "\($0) fps" })
        parts.appendIfPresent(codecName(of: inbound))
        parts.appendIfPresent(inbound.string("decoderImplementation"))
        parts.append(contentsOf: receiveQuality(of: inbound))
        parts.appendIfPresent(inbound.int("freezeCount").map { "\($0) freezes" })
        parts.appendIfPresent(inbound.int("framesDropped").map { "\($0) frames dropped" })

        return parts
    }

    private func outboundParts(of outbound: RTCStatistics) -> [String] {
        var parts = [String]()

        if let width = outbound.int("frameWidth"), let height = outbound.int("frameHeight") {
            parts.append("\(width)x\(height)")
        }

        parts.appendIfPresent(outbound.int("framesPerSecond").map { "\($0) fps" })
        parts.appendIfPresent(codecName(of: outbound))
        parts.appendIfPresent(outbound.string("encoderImplementation"))
        parts.appendIfPresent(bitrateKbps(of: outbound, bytesKey: "bytesSent").map { "\($0) kbps" })

        if let reason = outbound.string("qualityLimitationReason"), reason != "none" {
            parts.append("limited by \(reason)")
        }

        if let remoteInbound = stats(ofType: "remote-inbound-rtp").first(where: { $0.string("localId") == outbound.id }) {
            parts.appendIfPresent(remoteInbound.double("fractionLost").map { String(format: "remote loss %.1f%%", $0 * 100) })
        }

        if outbound.bool("active") == false {
            parts.append("inactive")
        }

        return parts
    }

    private func receiveQuality(of inbound: RTCStatistics) -> [String] {
        var parts = [String]()

        parts.appendIfPresent(bitrateKbps(of: inbound, bytesKey: "bytesReceived").map { "\($0) kbps" })
        parts.appendIfPresent(packetLossPercent(of: inbound).map { String(format: "loss %.1f%%", $0) })
        parts.appendIfPresent(inbound.double("jitter").map { "jitter \(Int($0 * 1000)) ms" })

        return parts
    }

    private var selectedCandidatePair: RTCStatistics? {
        if let pairId = stats(ofType: "transport").compactMap({ $0.string("selectedCandidatePairId") }).first {
            return report.statistics[pairId]
        }

        return stats(ofType: "candidate-pair").first { $0.string("state") == "succeeded" && $0.bool("nominated") == true }
    }

    // E.g. "relay/udp (turn tls) ↔ srflx · rtt 45 ms"
    private var selectedConnectionSummary: String? {
        guard let candidatePair = selectedCandidatePair,
              let localCandidate = candidatePair.string("localCandidateId").flatMap({ report.statistics[$0] }),
              let remoteCandidate = candidatePair.string("remoteCandidateId").flatMap({ report.statistics[$0] })
        else { return nil }

        var local = localCandidate.string("candidateType") ?? "?"
        local.appendIfPresent(localCandidate.string("protocol").map { "/\($0)" })
        local.appendIfPresent(localCandidate.string("relayProtocol").map { " (turn \($0))" })

        var summary = "\(local) ↔ \(remoteCandidate.string("candidateType") ?? "?")"
        summary.appendIfPresent(candidatePair.double("currentRoundTripTime").map { " · rtt \(Int($0 * 1000)) ms" })

        return summary
    }

    private func codecName(of rtpStats: RTCStatistics) -> String? {
        guard let codec = rtpStats.string("codecId").flatMap({ report.statistics[$0] }),
              let mimeType = codec.string("mimeType")
        else { return nil }

        return mimeType.components(separatedBy: "/").last
    }

    private func bitrateKbps(of rtpStats: RTCStatistics, bytesKey: String) -> Int? {
        guard let previousStats = previous?.statistics[rtpStats.id],
              let bytes = rtpStats.double(bytesKey), let previousBytes = previousStats.double(bytesKey),
              rtpStats.timestamp_us > previousStats.timestamp_us
        else { return nil }

        // Bits per millisecond is kbit/s
        return Int((bytes - previousBytes) * 8 / ((rtpStats.timestamp_us - previousStats.timestamp_us) / 1000))
    }

    // Since the previous report if there is one, otherwise over the whole connection
    private func packetLossPercent(of inbound: RTCStatistics) -> Double? {
        guard var lost = inbound.double("packetsLost"), var received = inbound.double("packetsReceived") else { return nil }

        if let previousStats = previous?.statistics[inbound.id],
           let previousLost = previousStats.double("packetsLost"), let previousReceived = previousStats.double("packetsReceived") {
            lost -= previousLost
            received -= previousReceived
        }

        guard lost + received > 0 else { return nil }

        return max(0, lost) / (lost + received) * 100
    }

    private func inboundRtp(kind: String) -> RTCStatistics? {
        stats(ofType: "inbound-rtp").first { $0.string("kind") == kind }
    }

    private func stats(ofType type: String) -> [RTCStatistics] {
        report.statistics.values.filter { $0.type == type }.sorted { $0.id < $1.id }
    }
}

private extension RTCStatistics {

    func string(_ key: String) -> String? {
        values[key] as? String
    }

    func double(_ key: String) -> Double? {
        (values[key] as? NSNumber)?.doubleValue
    }

    func int(_ key: String) -> Int? {
        double(key).map { Int($0.rounded()) }
    }

    func bool(_ key: String) -> Bool? {
        (values[key] as? NSNumber)?.boolValue
    }
}

private extension Array where Element == String {

    mutating func appendIfPresent(_ element: String?) {
        if let element {
            append(element)
        }
    }
}

private extension String {

    mutating func appendIfPresent(_ string: String?) {
        if let string {
            append(string)
        }
    }
}
