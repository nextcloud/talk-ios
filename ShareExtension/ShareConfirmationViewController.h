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
#import <UIKit/UIPageControl.h>

#import "NCRoom.h"
#import "NCDatabaseManager.h"
#import "ShareConfirmationCollectionViewCell.h"
#import "ShareItem.h"
#import "ShareItemController.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum ShareConfirmationType {
    ShareConfirmationTypeText = 0,
    ShareConfirmationTypeItem,
    ShareConfirmationTypeObjectShare
} ShareConfirmationType;

@class ShareConfirmationViewController;
@protocol ShareConfirmationViewControllerDelegate <NSObject>

- (void)shareConfirmationViewControllerDidFailed:(ShareConfirmationViewController *)viewController;
- (void)shareConfirmationViewControllerDidFinish:(ShareConfirmationViewController *)viewController;

@end

@interface ShareConfirmationViewController : UIViewController

@property (weak, nonatomic) id<ShareConfirmationViewControllerDelegate> delegate;

@property (strong, nonatomic) NCRoom *room;
@property (strong, nonatomic) TalkAccount *account;
@property (strong, nonatomic) ServerCapabilities *serverCapabilities;
@property (assign, nonatomic) ShareConfirmationType type;
@property (assign, nonatomic) BOOL isModal;
@property (assign, nonatomic) BOOL forwardingMessage;
@property (strong, nonatomic) ShareItemController *shareItemController;

@property (weak, nonatomic) IBOutlet NSLayoutConstraint *bottomSpacer;
@property (weak, nonatomic) IBOutlet UIView *toBackgroundView;
@property (weak, nonatomic) IBOutlet UILabel *toLabel;
@property (weak, nonatomic) IBOutlet UITextView *shareTextView;
@property (weak, nonatomic) IBOutlet UICollectionView *shareCollectionView;
@property (weak, nonatomic) IBOutlet UIPageControl *pageControl;
@property (weak, nonatomic) IBOutlet UIToolbar *itemToolbar;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *removeItemButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *cropItemButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *previewItemButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *addItemButton;


- (id)initWithRoom:(NCRoom *)room account:(TalkAccount *)account serverCapabilities:(ServerCapabilities *)serverCapabilities;
- (void)shareText:(NSString *)text;
- (void)shareObjectShareMessage:(NCChatMessage *)objectShareMessage;

@end

NS_ASSUME_NONNULL_END
