/**
 * SPDX-FileCopyrightText: 2021 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Intents/INInteraction.h>
#import <Intents/INSendMessageIntent.h>
#import <Intents/INStartCallIntent.h>
#import <Intents/INSendMessageIntent+UserNotifications.h>
#import <Intents/INSpeakableString.h>
#import <Intents/INOutgoingMessageType.h>
#import <Intents/INImage.h>
#import <Intents/INPerson.h>
#import <Intents/INPersonHandle.h>
#import <IntentsUI/INImage+IntentsUI.h>

#import <SDWebImage/SDWebImageManager.h>

#import "NCIntentController.h"
#import "TalkAccount.h"

#import "NextcloudTalk-Swift.h"

@implementation NCIntentController

+ (NCIntentController *)sharedInstance
{
    static dispatch_once_t once;
    static NCIntentController *sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)getInteractionForRoom:(NCRoom *)room withTitle:(NSString *)title withCompletionBlock:(GetInteractionForRoomCompletionBlock)block
{
    (void)[[AvatarManager shared] getAvatarFor:room with:UIUserInterfaceStyleLight completionBlock:^(UIImage *avatarImage) {
        if (!avatarImage) {
            if (block) {
                block(nil);
            }
            return;
        }

        if (avatarImage.sd_isVector) {
            // INImage does not support SVGs -> render them
            avatarImage = [[AvatarManager shared] createRenderedImageWithImage:avatarImage];
        }

        INSpeakableString *groupName = [[INSpeakableString alloc] initWithSpokenPhrase:title];
        INPersonHandle *handle = [[INPersonHandle alloc] initWithValue:nil type:INPersonHandleTypeUnknown];
        INImage *image = [INImage imageWithUIImage:avatarImage];

        INPerson *person = [[INPerson alloc]
                            initWithPersonHandle:handle
                            nameComponents:nil
                            displayName:title
                            image:image
                            contactIdentifier:nil
                            customIdentifier:room.internalId];

        INSendMessageIntent *sendMessageIntent = [[INSendMessageIntent alloc] initWithRecipients:nil
                                                                             outgoingMessageType:INOutgoingMessageTypeOutgoingMessageText
                                                                                         content:nil
                                                                              speakableGroupName:groupName
                                                                          conversationIdentifier:room.internalId
                                                                                     serviceName:nil
                                                                                          sender:person
                                                                                     attachments:nil];

        INInteraction *interaction = [[INInteraction alloc] initWithIntent:sendMessageIntent response:nil];
        interaction.direction = INInteractionDirectionIncoming;

        [interaction donateInteractionWithCompletion:^(NSError * _Nullable error) {
            if (block) {
                if (error) {
                    NSLog(@"Interaction donation failed: %@", error.description);
                    block(nil);
                } else {
                    block(sendMessageIntent);
                }
            }
        }];
    }];
}

- (void)donateSendMessageIntentForRoom:(NCRoom *)room
{
    [self donateCallIntentForRoom:room];

    // When the system suggest to write a message to "someone", we don't receive the conversationIdentifier.
    // Therefore we also add a recipient here, although it's technically not a "Person", but a "Room".
    INPersonHandle *handle = [[INPersonHandle alloc] initWithValue:nil type:INPersonHandleTypeUnknown];
    INPerson *recipient = [[INPerson alloc]
                           initWithPersonHandle:handle
                           nameComponents:nil
                           displayName:room.displayName
                           image:nil
                           contactIdentifier:nil
                           customIdentifier:room.internalId];

    INSpeakableString *groupName = [[INSpeakableString alloc] initWithSpokenPhrase:room.displayName];
    INSendMessageIntent *sendMessageIntent = [[INSendMessageIntent alloc] initWithRecipients:@[recipient]
                                                                         outgoingMessageType:INOutgoingMessageTypeOutgoingMessageText
                                                                                     content:nil
                                                                          speakableGroupName:groupName
                                                                      conversationIdentifier:room.internalId
                                                                                 serviceName:nil
                                                                                      sender:nil
                                                                                 attachments:nil];

    (void)[[AvatarManager shared] getAvatarFor:room with:UIUserInterfaceStyleLight completionBlock:^(UIImage *image) {
        if (image) {
            if (image.sd_isVector) {
                // INImage does not support SVGs -> render them
                image = [[AvatarManager shared] createRenderedImageWithImage:image];
            }

            INImage *intentImage = [INImage imageWithUIImage:image];
            [sendMessageIntent setImage:intentImage forParameterNamed:@"speakableGroupName"];
            [self donateMessageSentIntent:sendMessageIntent];
        }
    }];
}

- (void)donateCallIntentForRoom:(NCRoom *)room
{
    // Siri needs app-specific people in the calling domain, not only in the
    // messaging domain. Donate one-to-one Talk rooms as native Talk call
    // destinations. The prefixed custom identifier is later used by the main
    // app to keep Talk calls distinct from PSTN calls.
    if (room.type != kNCRoomTypeOneToOne || !room.canStartCall || room.internalId.length == 0) {
        return;
    }

    NSString *customIdentifier = [@"talk-room:" stringByAppendingString:room.internalId];
    NSString *handleValue = room.name.length > 0 ? room.name : room.displayName;
    INPersonHandle *handle = [[INPersonHandle alloc] initWithValue:handleValue type:INPersonHandleTypeUnknown];
    INPerson *person = [[INPerson alloc]
                        initWithPersonHandle:handle
                        nameComponents:nil
                        displayName:room.displayName
                        image:nil
                        contactIdentifier:nil
                        customIdentifier:customIdentifier];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    INStartCallIntent *callIntent = [[INStartCallIntent alloc]
                                     initWithCallRecordFilter:nil
                                     callRecordToCallBack:nil
                                     audioRoute:INCallAudioRouteUnknown
                                     destinationType:INCallDestinationTypeNormal
                                     contacts:@[person]
                                     callCapability:INCallCapabilityAudioCall];
#pragma clang diagnostic pop

    INInteraction *interaction = [[INInteraction alloc] initWithIntent:callIntent response:nil];
    interaction.direction = INInteractionDirectionOutgoing;
    [interaction donateInteractionWithCompletion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to donate Talk call intent for %@: %@", room.displayName, error.description);
        } else {
            NSLog(@"Talk call intent donated for %@", room.displayName);
        }
    }];
}

- (void)donateMessageSentIntent:(INSendMessageIntent *)sendMessageIntent
{
    INInteraction *interaction = [[INInteraction alloc] initWithIntent:sendMessageIntent response:nil];
    [interaction donateInteractionWithCompletion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to donate sendMessageIntent: %@", [error description]);
        } else {
            NSLog(@"SendMessageIntent successfully donated");
        }
    }];
}

@end
