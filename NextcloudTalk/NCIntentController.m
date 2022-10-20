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
#import <Intents/INSendMessageIntent_Deprecated.h>
#import <Intents/INSpeakableString.h>
#import <Intents/INOutgoingMessageType.h>
#import <Intents/INImage.h>
#import <IntentsUI/INImage+IntentsUI.h>

#import "NCIntentController.h"
#import "NCAPIController.h"
#import "NCDatabaseManager.h"

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
    switch (room.type) {
        case kNCRoomTypeOneToOne:
        {
            TalkAccount *account = [[NCDatabaseManager sharedInstance] talkAccountForAccountId:room.accountId];
            [[NCAPIController sharedInstance] getUserAvatarForUser:room.name andSize:512 usingAccount:account withCompletionBlock:^(UIImage *image, NSError *error) {
                if (image) {
                    [sendMessageIntent setImage:[INImage imageWithUIImage:image] forParameterNamed:@"speakableGroupName"];
                    [self donateMessageSentIntent:sendMessageIntent];
                }
            }];
            break;
        }
        case kNCRoomTypeGroup:
        {
            [sendMessageIntent setImage:[INImage imageWithUIImage:[UIImage imageNamed:@"group-avatar"]] forParameterNamed:@"speakableGroupName"];
            [self donateMessageSentIntent:sendMessageIntent];
            break;
        }

        case kNCRoomTypePublic:
        {
            [sendMessageIntent setImage:[INImage imageWithUIImage:[UIImage imageNamed:@"public-avatar"]] forParameterNamed:@"speakableGroupName"];
            [self donateMessageSentIntent:sendMessageIntent];
            break;
        }

        default:
            break;
    }
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
