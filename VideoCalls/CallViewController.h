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
@property (nonatomic, copy) NSString *room;

@property (nonatomic, strong) IBOutlet RTCCameraPreviewView *localVideoView;

- (instancetype)initCallInRoom:(NSString *)room asUser:(NSString*)displayName;

@end
