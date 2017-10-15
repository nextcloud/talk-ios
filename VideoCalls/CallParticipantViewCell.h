//
//  CallParticipantViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 06.10.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RTCEAGLVideoView;

extern NSString *const kCallParticipantCellIdentifier;
extern NSString *const kCallParticipantCellNibName;

@class RTCVideoTrack;

@interface CallParticipantViewCell : UICollectionViewCell

@property (nonatomic, strong)  NSString *displayName;
@property (nonatomic, assign)  BOOL audioDisabled;
@property (nonatomic, assign)  BOOL videoDisabled;

@property (nonatomic, weak) IBOutlet UIView *peerVideoView;
@property (nonatomic, weak) IBOutlet UILabel *peerNameLabel;
@property (nonatomic, weak) IBOutlet UIImageView *audioOffIndicator;

- (void)setVideoView:(RTCEAGLVideoView *)videoView;

@end
