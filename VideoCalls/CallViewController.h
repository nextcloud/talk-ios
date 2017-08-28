//
//  CallViewController.h
//  VideoCalls
//
//  Created by Ivan Sein on 31.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <WebRTC/WebRTC.h>

@class CallViewController;
@protocol CallViewControllerDelegate <NSObject>

- (void)viewControllerDidFinish:(CallViewController *)viewController;

@end

@interface CallViewController : UIViewController

@property(nonatomic, weak) id<CallViewControllerDelegate> delegate;

@property (strong, nonatomic) IBOutlet RTCCameraPreviewView *localVideoView;
@property (strong, nonatomic) IBOutlet UIView *remoteView;
@property (strong, nonatomic) IBOutlet UIButton *hangupButton;

- (instancetype)initWithSessionId:(NSString *)sessionId;

@end
