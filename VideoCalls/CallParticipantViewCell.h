//
//  CallParticipantViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 06.10.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <WebRTC/WebRTC.h>

extern NSString *const kCallParticipantCellIdentifier;
extern NSString *const kCallParticipantCellNibName;

@class CallParticipantViewCell;
@protocol CallParticipantViewCellDelegate <NSObject>
- (void)cellWantsToPresentScreenSharing:(CallParticipantViewCell *)participantCell;
@end

@interface CallParticipantViewCell : UICollectionViewCell

@property (nonatomic, weak) id<CallParticipantViewCellDelegate> actionsDelegate;

@property (nonatomic, strong)  NSString *peerId;
@property (nonatomic, strong)  NSString *displayName;
@property (nonatomic, assign)  BOOL audioDisabled;
@property (nonatomic, assign)  BOOL videoDisabled;
@property (nonatomic, assign)  BOOL screenShared;
@property (nonatomic, assign)  RTCIceConnectionState connectionState;

@property (nonatomic, weak) IBOutlet UIView *peerVideoView;
@property (nonatomic, weak) IBOutlet UILabel *peerNameLabel;
@property (nonatomic, weak) IBOutlet UIImageView *peerAvatarImageView;
@property (nonatomic, weak) IBOutlet UIButton *audioOffIndicator;
@property (nonatomic, weak) IBOutlet UIButton *screensharingIndicator;
@property (weak, nonatomic) IBOutlet UIView *buttonsContainerView;


- (void)setVideoView:(RTCEAGLVideoView *)videoView;
- (void)setSpeaking:(BOOL)speaking;
- (void)setUserAvatar:(NSString *)userId;
- (void)resizeRemoteVideoView;

@end
