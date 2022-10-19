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

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class ShareViewController;
@class NCChatMessage;
@protocol ShareViewControllerDelegate <NSObject>

- (void)shareViewControllerDidCancel:(ShareViewController *)viewController;

@end

@interface ShareViewController : UITableViewController

@property (weak, nonatomic) id<ShareViewControllerDelegate> delegate;

@property (strong, nonatomic) UIViewController *chatViewController;
@property (strong, nonatomic) NSString *forwardMessage;
@property (strong, nonatomic) NCChatMessage *forwardObjectShareMessage;
@property (assign, nonatomic) BOOL forwarding;

- (id)initToForwardMessage:(NSString *)message fromChatViewController:(UIViewController *)chatViewController;
- (id)initToForwardObjectShareMessage:(NCChatMessage *)objectShareMessage fromChatViewController:(UIViewController *)chatViewController;

@end

NS_ASSUME_NONNULL_END
