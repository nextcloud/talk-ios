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
#import <WebRTC/WebRTC.h>

extern NSString *const kCallParticipantCellIdentifier;
extern NSString *const kCallParticipantCellNibName;
extern CGFloat const kCallParticipantCellMinHeight;

@class CallParticipantViewCell;
@protocol CallParticipantViewCellDelegate <NSObject>
- (void)cellWantsToPresentScreenSharing:(CallParticipantViewCell *)participantCell;
- (void)cellWantsToChangeZoom:(CallParticipantViewCell *)participantCell showOriginalSize:(BOOL)showOriginalSize;
@end

@interface CallParticipantViewCell : UICollectionViewCell

@property (nonatomic, weak) id<CallParticipantViewCellDelegate> actionsDelegate;

@property (nonatomic, strong)  NSString *peerId;
@property (nonatomic, strong)  NSString *displayName;
@property (nonatomic, assign)  BOOL audioDisabled;
@property (nonatomic, assign)  BOOL videoDisabled;
@property (nonatomic, assign)  BOOL screenShared;
@property (nonatomic, assign)  BOOL showOriginalSize;
@property (nonatomic, assign)  RTCIceConnectionState connectionState;

@property (nonatomic, weak) IBOutlet UIView *peerVideoView;
@property (nonatomic, weak) IBOutlet UILabel *peerNameLabel;
@property (nonatomic, weak) IBOutlet UIImageView *peerAvatarImageView;
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
- (void)setUserAvatar:(NSString *)userId withDisplayName:(NSString *)displayName;
- (void)setRemoteVideoSize:(CGSize)size;
- (void)setRaiseHand:(BOOL)raised;
- (void)resizeRemoteVideoView;

@end
