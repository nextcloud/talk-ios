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
