/**
 * @copyright Copyright (c) 2021 Marcel Müller <marcel-mueller@gmx.de>
 *
 * @author Marcel Müller <marcel-mueller@gmx.de>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import <Intents/INInteraction.h>
#import <Intents/INSendMessageIntent.h>
#import <Intents/INSendMessageIntent+UserNotifications.h>
#import <Intents/INSpeakableString.h>
#import <Intents/INOutgoingMessageType.h>
#import <Intents/INImage.h>
#import <Intents/INPerson.h>
#import <Intents/INPersonHandle.h>
#import <IntentsUI/INImage+IntentsUI.h>

#import "NCIntentController.h"
#import "NCAPIController.h"
#import "NCDatabaseManager.h"

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
                            customIdentifier:nil];

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
    INSpeakableString *groupName = [[INSpeakableString alloc] initWithSpokenPhrase:room.displayName];
    INSendMessageIntent *sendMessageIntent = [[INSendMessageIntent alloc] initWithRecipients:nil
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
