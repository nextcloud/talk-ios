/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
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

#import "ChatTableViewCell.h"

typedef void (^GetMenuUserActionsForMessageCompletionBlock)(NSArray *menuItems);

@interface ChatTableViewCell () <UITextFieldDelegate>
@property (nonatomic, strong) DRCellSlideGestureRecognizer *replyGestureRecognizer;
@end

@implementation ChatTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization
    }
    return self;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.messageId = -1;
    self.message = nil;
    [self removeGestureRecognizer:self.replyGestureRecognizer];
}

- (void)addReplyGestureWithActionBlock:(DRCellSlideActionBlock)block
{
    self.replyGestureRecognizer = [DRCellSlideGestureRecognizer new];
    self.replyGestureRecognizer.leftActionStartPosition = 80;
    DRCellSlideAction *action = [DRCellSlideAction actionForFraction:0.2];
    action.behavior = DRCellSlideActionPullBehavior;
    action.activeColor = [UIColor labelColor];
    action.inactiveColor = [UIColor placeholderTextColor];
    action.activeBackgroundColor = self.backgroundColor;
    action.inactiveBackgroundColor = self.backgroundColor;
    action.icon = [UIImage imageNamed:@"reply"];

    [action setWillTriggerBlock:^(UITableView *tableView, NSIndexPath *indexPath) {
        block(tableView, indexPath);
    }];

    [action setDidChangeStateBlock:^(DRCellSlideAction *action, BOOL active) {
        if (active) {
            // Actuate `Peek` feedback (weak boom)
            AudioServicesPlaySystemSound(1519);
        }
    }];

    [self.replyGestureRecognizer addActions:action];
    [self addGestureRecognizer:self.replyGestureRecognizer];
}

- (UIMenu *)getDeferredUserMenuForMessage:(NCChatMessage *)message
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    if (![message.actorType isEqualToString:@"users"] || [message.actorId isEqualToString:activeAccount.userId]) {
        return nil;
    }

    UIDeferredMenuElement *deferredMenuElement;

    if (@available(iOS 15.0, *)) {
        // When iOS 15 is available, we can use an uncached provider so local time is not cached for example
        deferredMenuElement = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^ _Nonnull completion)(NSArray<UIMenuElement *> * _Nonnull)) {
            [self getMenuUserActionsForMessage:message withCompletionBlock:^(NSArray *menuItems) {
                completion(menuItems);
            }];
        }];
    } else {
        deferredMenuElement = [UIDeferredMenuElement elementWithProvider:^(void (^ _Nonnull completion)(NSArray<UIMenuElement *> * _Nonnull)) {
            [self getMenuUserActionsForMessage:message withCompletionBlock:^(NSArray *menuItems) {
                completion(menuItems);
            }];
        }];
    }

    return [UIMenu menuWithTitle:message.actorDisplayName children:@[deferredMenuElement]];
}

- (void)getMenuUserActionsForMessage:(NCChatMessage *)message withCompletionBlock:(GetMenuUserActionsForMessageCompletionBlock)block
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [[NCAPIController sharedInstance] getUserActionsForUser:message.actorId usingAccount:activeAccount withCompletionBlock:^(NSDictionary *userActions, NSError *error) {
        if (error) {
            if (block) {
                UIAction *errorAction = [UIAction actionWithTitle:NSLocalizedString(@"No actions available", nil) image:nil identifier:nil handler:^(UIAction *action) {}];
                errorAction.attributes = UIMenuElementAttributesDisabled;
                block(@[errorAction]);
            }

            return;
        }

        NSArray *actions = [userActions objectForKey:@"actions"];
        if (![actions isKindOfClass:[NSArray class]]) {
            if (block) {
                UIAction *errorAction = [UIAction actionWithTitle:NSLocalizedString(@"No actions available", nil) image:nil identifier:nil handler:^(UIAction *action) {}];
                errorAction.attributes = UIMenuElementAttributesDisabled;
                block(@[errorAction]);
            }

            return;
        }

        NSMutableArray *items = [[NSMutableArray alloc] init];

        for (NSDictionary *action in actions) {
            NSString *appId = [action objectForKey:@"appId"];
            NSString *title = [action objectForKey:@"title"];
            NSString *link = [action objectForKey:@"hyperlink"];

            // Talk to user action
            if ([appId isEqualToString:@"spreed"]) {
                UIAction *talkAction = [UIAction actionWithTitle:title
                                                           image:[[UIImage imageNamed:@"navigationLogo"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                                                      identifier:nil
                                                         handler:^(UIAction *action) {
                    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
                    NSString *userId = [userActions objectForKey:@"userId"];
                    [userInfo setObject:userId forKey:@"actorId"];
                    [[NSNotificationCenter defaultCenter] postNotificationName:NCChatViewControllerTalkToUserNotification
                                                                        object:self
                                                                      userInfo:userInfo];
                }];

                [items addObject:talkAction];
                continue;
            }

            // Other user actions
            UIAction *otherAction = [UIAction actionWithTitle:title
                                                        image:nil
                                                   identifier:nil
                                                      handler:^(UIAction *action) {
                NSURL *actionURL = [NSURL URLWithString:[link stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
                [[UIApplication sharedApplication] openURL:actionURL options:@{} completionHandler:nil];
            }];

            if ([appId isEqualToString:@"profile"]) {
                [otherAction setImage:[UIImage systemImageNamed:@"person.fill"]];
            } else if ([appId isEqualToString:@"email"]) {
                [otherAction setImage:[UIImage systemImageNamed:@"envelope.fill"]];
            } else if ([appId isEqualToString:@"timezone"]) {
                [otherAction setImage:[UIImage systemImageNamed:@"clock"]];
            } else if ([appId isEqualToString:@"social"]) {
                [otherAction setImage:[UIImage systemImageNamed:@"heart.fill"]];
            }

            [items addObject:otherAction];
        }

        if (block) {
            block(items);
        }
    }];
}

@end
