//
// SPDX-FileCopyrightText: 2021 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Intents
import IntentsUI
import SDWebImage

class NCIntentController: NSObject {

    private static let shared = NCIntentController()

    static func sharedInstance() -> NCIntentController {
        return shared
    }

    func getInteractionFor(_ room: NCRoom, withTitle title: String, withCompletionBlock block: @escaping (INSendMessageIntent?) -> Void) {
        _ = AvatarManager.shared.getAvatar(for: room, with: .light) { avatarImage in
            guard let avatarImage else {
                block(nil)
                return
            }

            let groupName = INSpeakableString(spokenPhrase: title)
            let handle = INPersonHandle(value: nil, type: .unknown)
            let person = INPerson(personHandle: handle,
                                  nameComponents: nil,
                                  displayName: title,
                                  image: self.intentImage(from: avatarImage),
                                  contactIdentifier: nil,
                                  customIdentifier: room.internalId)

            let sendMessageIntent = INSendMessageIntent(recipients: nil,
                                                        outgoingMessageType: .outgoingMessageText,
                                                        content: nil,
                                                        speakableGroupName: groupName,
                                                        conversationIdentifier: room.internalId,
                                                        serviceName: nil,
                                                        sender: person,
                                                        attachments: nil)

            let interaction = INInteraction(intent: sendMessageIntent, response: nil)
            interaction.direction = .incoming
            interaction.donate { error in
                if let error {
                    NCLog.log("Interaction donation failed: \(error.localizedDescription)")
                    block(nil)
                } else {
                    block(sendMessageIntent)
                }
            }
        }
    }

    func donateSendMessageIntent(for room: NCRoom) {
        // When the system suggests to write a message to "someone", we don't receive the conversationIdentifier.
        // Therefore we also add a recipient here, although it's technically not a "Person", but a "Room".
        let handle = INPersonHandle(value: nil, type: .unknown)
        let recipient = INPerson(personHandle: handle,
                                 nameComponents: nil,
                                 displayName: room.displayName,
                                 image: nil,
                                 contactIdentifier: nil,
                                 customIdentifier: room.internalId)

        let groupName = INSpeakableString(spokenPhrase: room.displayName)
        let sendMessageIntent = INSendMessageIntent(recipients: [recipient],
                                                    outgoingMessageType: .outgoingMessageText,
                                                    content: nil,
                                                    speakableGroupName: groupName,
                                                    conversationIdentifier: room.internalId,
                                                    serviceName: nil,
                                                    sender: nil,
                                                    attachments: nil)

        _ = AvatarManager.shared.getAvatar(for: room, with: .light) { image in
            guard let image else { return }

            sendMessageIntent.setImage(self.intentImage(from: image), forParameterNamed: \.speakableGroupName)
            self.donateMessageSentIntent(sendMessageIntent)
        }
    }

    func donateCallIntent(for room: NCRoom) {
        guard room.type == .oneToOne,
              room.supportsCalling,
              room.userCanStartCall,
              !room.internalId.isEmpty else {
            return
        }

        let handleValue = room.name.isEmpty ? room.displayName : room.name
        let person = INPerson(
            personHandle: INPersonHandle(value: handleValue, type: .unknown),
            nameComponents: nil,
            displayName: room.displayName,
            image: nil,
            contactIdentifier: nil,
            customIdentifier: "talk-room:\(room.internalId)"
        )

        let intent = INStartCallIntent(
            audioRoute: .unknown,
            destinationType: .normal,
            contacts: [person],
            recordTypeForRedialing: .unknown,
            callCapability: .audioCall
        )

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .outgoing
        interaction.donate { error in
            if let error {
                NCLog.log("Failed to donate Talk call intent: \(error.localizedDescription)")
            }
        }
    }

    private func donateMessageSentIntent(_ sendMessageIntent: INSendMessageIntent) {
        let interaction = INInteraction(intent: sendMessageIntent, response: nil)
        interaction.donate { error in
            if let error {
                NCLog.log("Failed to donate sendMessageIntent: \(error.localizedDescription)")
            }
        }
    }

    private func intentImage(from image: UIImage) -> INImage? {
        // INImage does not support SVGs, so they need to be rendered first
        let renderedImage = image.sd_isVector ? AvatarManager.shared.createRenderedImage(image: image) : image
        return renderedImage.flatMap { INImage(uiImage: $0) }
    }
}
