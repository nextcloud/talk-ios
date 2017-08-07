//
//  CallViewController.h
//  VideoCalls
//
//  Created by Ivan Sein on 31.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <WebRTC/WebRTC.h>

@interface CallViewController : UIViewController

@property (strong, nonatomic) IBOutlet RTCCameraPreviewView *localVideoView;
@property (strong, nonatomic) IBOutlet UIView *remoteView;

- (instancetype)initWithSessionId:(NSString *)sessionId;

@end
