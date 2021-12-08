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

#import <WebRTC/RTCCameraPreviewView.h>
#import "AvatarBackgroundImageView.h"
#import "NCRoom.h"

@class CallViewController;
@protocol CallViewControllerDelegate <NSObject>

- (void)callViewControllerWantsToBeDismissed:(CallViewController *)viewController;
- (void)callViewControllerWantsVideoCallUpgrade:(CallViewController *)viewController;
- (void)callViewControllerDidFinish:(CallViewController *)viewController;

@end

@interface CallViewController : UIViewController

@property (nonatomic, weak) id<CallViewControllerDelegate> delegate;
@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, assign) BOOL videoDisabledAtStart;

@property (nonatomic, strong) IBOutlet RTCCameraPreviewView *localVideoView;
@property (nonatomic, strong) IBOutlet UIView *screensharingView;
@property (nonatomic, strong) IBOutlet UIButton *closeScreensharingButton;
@property (nonatomic, strong) IBOutlet UIButton *toggleChatButton;
@property (nonatomic, strong) IBOutlet UIView *waitingView;
@property (nonatomic, strong) IBOutlet AvatarBackgroundImageView *avatarBackgroundImageView;
@property (nonatomic, strong) IBOutlet UILabel *waitingLabel;
@property (nonatomic, strong) IBOutlet UILabel *conversationName;
@property (nonatomic, strong) IBOutlet UILabel *conversationType;

- (instancetype)initCallInRoom:(NCRoom *)room asUser:(NSString*)displayName audioOnly:(BOOL)audioOnly;

@end
