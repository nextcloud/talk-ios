//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

// A small card shown after leaving a call: how long it took, who was there and how many reactions were sent.
// Everything is collected on the device during the call, nothing is sent anywhere.
struct CallRecap: Equatable {

    let roomToken: String
    let roomName: String
    let duration: TimeInterval
    // Display names of the other participants, in the order they joined
    let participantNames: [String]
    let reactionCount: Int

    // Short calls or calls without anybody else are not worth a summary
    static let minimumDuration: TimeInterval = 2 * 60

    var isWorthShowing: Bool {
        return duration >= Self.minimumDuration && !participantNames.isEmpty
    }

    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .short

        return formatter.string(from: duration) ?? ""
    }

    // "Alice", "Alice and Bob", "Alice, Bob and 3 others"
    var participantsDescription: String {
        let names = participantNames

        switch names.count {
        case 0:
            return ""
        case 1:
            return names[0]
        case 2:
            return String(format: NSLocalizedString("%@ and %@", comment: "Alice and Bob"), names[0], names[1])
        case 3:
            return String(format: NSLocalizedString("%@, %@ and %@", comment: "Alice, Bob and Charlie"), names[0], names[1], names[2])
        default:
            let others = names.count - 2
            let othersString = String.localizedStringWithFormat(NSLocalizedString("%ld others", comment: "Part of 'Alice, Bob and 3 others'"), others)
            return String(format: NSLocalizedString("%@, %@ and %@", comment: "Alice, Bob and Charlie"), names[0], names[1], othersString)
        }
    }
}

// Collects what happened during a call. The call view controller calls it from different threads.
class CallRecapCollector {

    private let lock = NSLock()
    private var startDate: Date?
    private var participantIds = [String]()
    private var participantNames = [String: String]()
    private var reactionCount = 0

    func callDidStart(at date: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        if startDate == nil {
            startDate = date
        }
    }

    func addParticipant(id: String, displayName: String) {
        lock.lock()
        defer { lock.unlock() }

        if !participantIds.contains(id) {
            participantIds.append(id)
        }

        // A guest might change the name during the call
        participantNames[id] = displayName
    }

    func addReaction() {
        lock.lock()
        defer { lock.unlock() }

        reactionCount += 1
    }

    func recap(for room: NCRoom, endDate: Date = Date()) -> CallRecap? {
        lock.lock()
        defer { lock.unlock() }

        guard let startDate, let token = room.token else { return nil }

        return CallRecap(roomToken: token,
                         roomName: room.displayName,
                         duration: endDate.timeIntervalSince(startDate),
                         participantNames: participantIds.compactMap { participantNames[$0] },
                         reactionCount: reactionCount)
    }
}

class CallRecapViewController: UIHostingController<CallRecapView> {

    init(recap: CallRecap, account: TalkAccount) {
        var closeHandler: (() -> Void)?

        let view = CallRecapView(recap: recap, account: account) {
            closeHandler?()
        }

        super.init(rootView: view)

        closeHandler = { [weak self] in
            self?.dismiss(animated: true)
        }

        if let sheet = self.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct CallRecapView: View {

    let recap: CallRecap
    let account: TalkAccount
    let onClose: () -> Void

    @State private var thanksState: ThanksState = .notSent

    enum ThanksState {
        case notSent, sending, sent, failed
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("👋")
                    .font(.system(size: 44))
                    .accessibilityHidden(true)
                Text(NSLocalizedString("Call ended", comment: ""))
                    .font(.title3.bold())
                Text(recap.roomName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.top, 20)

            HStack(spacing: 12) {
                RecapTile(value: recap.formattedDuration,
                          label: NSLocalizedString("Duration", comment: "Duration of a call"),
                          systemImage: "clock.fill")
                RecapTile(value: "\(recap.participantNames.count + 1)",
                          label: NSLocalizedString("People", comment: "Number of people in a call, including yourself"),
                          systemImage: "person.2.fill")
                RecapTile(value: "\(recap.reactionCount)",
                          label: NSLocalizedString("Reactions", comment: "Number of reactions sent in a call"),
                          systemImage: "face.smiling.inverse")
            }
            .padding(.horizontal)

            Text(String(format: NSLocalizedString("With %@", comment: "With Alice, Bob and 3 others"), recap.participantsDescription))
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    sendThanks()
                } label: {
                    Group {
                        switch thanksState {
                        case .notSent, .failed:
                            Text(NSLocalizedString("Say thanks 👋", comment: "Sends a thank you message into the chat after a call"))
                        case .sending:
                            ProgressView()
                        case .sent:
                            Label(NSLocalizedString("Thanks sent", comment: ""), systemImage: "checkmark")
                        }
                    }
                    .bold()
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(NCAppBranding.elementColor()))
                .controlSize(.large)
                .disabled(thanksState == .sending || thanksState == .sent)

                if thanksState == .failed {
                    Text(NSLocalizedString("Could not send message", comment: ""))
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                Button(NSLocalizedString("Close", comment: ""), action: onClose)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private func sendThanks() {
        thanksState = .sending

        let message = NSLocalizedString("Thanks for the call! 👋", comment: "Message sent into the chat after a call")

        _ = NCAPIController.sharedInstance().sendChatMessage(message, toRoom: recap.roomToken, threadTitle: nil, replyTo: -1,
                                                             referenceId: nil, silently: false, forAccount: account) { error in
            DispatchQueue.main.async {
                if error == nil {
                    HapticFeedback.success()
                    thanksState = .sent

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        onClose()
                    }
                } else {
                    HapticFeedback.error()
                    thanksState = .failed
                }
            }
        }
    }
}

private struct RecapTile: View {

    let value: String
    let label: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundColor(Color(NCAppBranding.elementColor()))
            Text(value)
                .font(.title3.bold())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(UIColor.secondarySystemBackground)))
        .accessibilityElement(children: .combine)
    }
}
