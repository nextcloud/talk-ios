/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>

#import <WebRTC/RTCCameraPreviewView.h>
#import "AvatarBackgroundImageView.h"
#import "NCRoom.h"
#import "NCChatTitleView.h"

@class CallViewController;
@class NCZoomableView;
@protocol CallViewControllerDelegate <NSObject>

- (void)callViewControllerWantsToBeDismissed:(CallViewController *)viewController;
- (void)callViewControllerWantsVideoCallUpgrade:(CallViewController *)viewController;
- (void)callViewControllerDidFinish:(CallViewController *)viewController;
- (void)callViewController:(CallViewController *)viewController wantsToSwitchCallFromCall:(NSString *)from toRoom:(NSString *)to;

@end

@interface CallViewController : UIViewController

@property (nonatomic, weak) id<CallViewControllerDelegate> delegate;
@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, assign) BOOL audioDisabledAtStart;
@property (nonatomic, assign) BOOL videoDisabledAtStart;
@property (nonatomic, assign) BOOL voiceChatModeAtStart;
@property (nonatomic, assign) BOOL initiator;
@property (nonatomic, assign) BOOL silentCall;
@property (nonatomic, assign) BOOL recordingConsent;

@property (nonatomic, strong) IBOutlet MTKView *localVideoView;
@property (nonatomic, strong) IBOutlet NCZoomableView *screensharingView;
@property (nonatomic, strong) IBOutlet UIButton *closeScreensharingButton;
@property (nonatomic, strong) IBOutlet UIButton *toggleChatButton;
@property (nonatomic, strong) IBOutlet UIView *waitingView;
@property (nonatomic, strong) IBOutlet AvatarBackgroundImageView *avatarBackgroundImageView;
@property (nonatomic, strong) IBOutlet UILabel *waitingLabel;
@property (nonatomic, strong) IBOutlet NCChatTitleView *titleView;
@property (nonatomic, strong) IBOutlet UILabel *callTimeLabel;
@property (nonatomic, strong) IBOutlet UIView *screenshareLabelContainer;
@property (nonatomic, strong) IBOutlet UILabel *screenshareLabel;
@property (nonatomic, strong) IBOutlet UIView *participantsLabelContainer;
@property (nonatomic, strong) IBOutlet UILabel *participantsLabel;

- (instancetype)initCallInRoom:(NCRoom *)room asUser:(NSString*)displayName audioOnly:(BOOL)audioOnly;
- (void)toggleChatView;

@end
