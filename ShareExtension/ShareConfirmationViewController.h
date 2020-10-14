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

#import "NCRoom.h"
#import "NCDatabaseManager.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum ShareConfirmationType {
    ShareConfirmationTypeText = 0,
    ShareConfirmationTypeImage,
    ShareConfirmationTypeFile,
    ShareConfirmationTypeImageFile
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
@property (strong, nonatomic) NSString *sharedText;
@property (strong, nonatomic) NSString *sharedImageName;
@property (strong, nonatomic) UIImage *sharedImage;
@property (strong, nonatomic) NSString *sharedFileName;
@property (strong, nonatomic) UIImage *sharedFileImage;
@property (strong, nonatomic) NSURL *sharedFileURL;
@property (strong, nonatomic) NSData *sharedFile;
@property (assign, nonatomic) BOOL isModal;


@property (weak, nonatomic) IBOutlet UIView *toBackgroundView;
@property (weak, nonatomic) IBOutlet UITextView *toTextView;
@property (weak, nonatomic) IBOutlet UITextView *shareTextView;
@property (weak, nonatomic) IBOutlet UIImageView *shareImageView;
@property (weak, nonatomic) IBOutlet UIImageView *shareFileImageView;
@property (weak, nonatomic) IBOutlet UITextView *shareFileTextView;

- (id)initWithRoom:(NCRoom *)room account:(TalkAccount *)account serverCapabilities:(ServerCapabilities *)serverCapabilities;
- (void)setSharedFileWithFileURL:(NSURL *)fileURL;
- (void)setSharedFileWithFileURL:(NSURL *)fileURL andFileName:(NSString *_Nullable)fileName;
- (void)setSharedImage:(UIImage *)image withImageName:(NSString *)imageName;

@end

NS_ASSUME_NONNULL_END
