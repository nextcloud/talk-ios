//
//  CallViewController.h
//  VideoCalls
//
//  Created by Ivan Sein on 31.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

#import <WebRTC/RTCCameraPreviewView.h>
#import "NCRoom.h"

@class CallViewController;
@protocol CallViewControllerDelegate <NSObject>

- (void)viewControllerDidFinish:(CallViewController *)viewController;

@end

@interface CallViewController : UIViewController

@property (nonatomic, weak) id<CallViewControllerDelegate> delegate;
@property (nonatomic, strong) NCRoom *room;

@property (nonatomic, strong) IBOutlet RTCCameraPreviewView *localVideoView;
@property (nonatomic, strong) IBOutlet UIImageView *localAvatarView;
@property (nonatomic, strong) IBOutlet UIView *waitingView;
@property (nonatomic, strong) IBOutlet UIImageView *waitingImageView;
@property (nonatomic, strong) IBOutlet UILabel *waitingLabel;

- (instancetype)initCallInRoom:(NCRoom *)room asUser:(NSString*)displayName;

@end
