/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <UIKit/UIKit.h>
#import <WebRTC/WebRTC.h>

extern NSString *const kCallParticipantCellIdentifier;
extern NSString *const kCallParticipantCellNibName;
extern CGFloat const kCallParticipantCellMinHeight;

@class CallParticipantViewCell;
@class MDCActivityIndicator;
@class AvatarImageView;
@class TalkActor;

@protocol CallParticipantViewCellDelegate <NSObject>
- (void)cellWantsToPresentScreenSharing:(CallParticipantViewCell *)participantCell;
- (void)cellWantsToChangeZoom:(CallParticipantViewCell *)participantCell showOriginalSize:(BOOL)showOriginalSize;
@end

@interface CallParticipantViewCell : UICollectionViewCell

@property (nonatomic, weak) id<CallParticipantViewCellDelegate> actionsDelegate;

@property (nonatomic, strong)  NSString *peerIdentifier;
@property (nonatomic, strong)  NSString *displayName;
@property (nonatomic, assign)  BOOL audioDisabled;
@property (nonatomic, assign)  BOOL videoDisabled;
@property (nonatomic, assign)  BOOL screenShared;
@property (nonatomic, assign)  BOOL showOriginalSize;
@property (nonatomic, assign)  RTCIceConnectionState connectionState;

@property (nonatomic, weak) IBOutlet UIView *peerVideoView;
@property (nonatomic, weak) IBOutlet UILabel *peerNameLabel;
@property (nonatomic, weak) IBOutlet MDCActivityIndicator *activityIndicator;
@property (nonatomic, weak) IBOutlet AvatarImageView *peerAvatarImageView;
@property (nonatomic, weak) IBOutlet UIButton *audioOffIndicator;
@property (nonatomic, weak) IBOutlet UIButton *screensharingIndicator;
@property (nonatomic, weak) IBOutlet UIButton *raisedHandIndicator;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *stackViewBottomConstraint;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *stackViewLeftConstraint;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *stackViewRightConstraint;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *screensharingIndiciatorRightConstraint;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *screensharingIndiciatorTopConstraint;


- (void)setVideoView:(RTCMTLVideoView *)videoView;
- (void)setSpeaking:(BOOL)speaking;
- (void)setAvatarForActor:(TalkActor *)actor;
- (CGSize)getRemoteVideoSize;
- (void)setRemoteVideoSize:(CGSize)size;
- (void)setRaiseHand:(BOOL)raised;
- (void)resizeRemoteVideoView;

@end
