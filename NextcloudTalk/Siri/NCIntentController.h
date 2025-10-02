/**
 * SPDX-FileCopyrightText: 2021 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <Intents/INSendMessageIntent.h>
#import <Intents/INSendMessageIntent+UserNotifications.h>

#import "NCRoom.h"

typedef void (^GetInteractionForRoomCompletionBlock)(INSendMessageIntent *sendMessageIntent);

@interface NCIntentController : NSObject

+ (instancetype)sharedInstance;

- (void)donateSendMessageIntentForRoom:(NCRoom *)room;
- (void)getInteractionForRoom:(NCRoom *)room withTitle:(NSString *)title withCompletionBlock:(GetInteractionForRoomCompletionBlock)block;

@end
