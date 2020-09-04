//
//  ShareConfirmationViewController.h
//  VideoCalls
//
//  Created by Ivan Sein on 01.09.20.
//  Copyright © 2020 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "NCRoom.h"
#import "NCDatabaseManager.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum ShareConfirmationType {
    ShareConfirmationTypeText = 0,
    ShareConfirmationTypeImage
} ShareConfirmationType;

@class ShareConfirmationViewController;
@protocol ShareConfirmationViewControllerDelegate <NSObject>

- (void)shareConfirmationViewControllerDidFailed:(ShareConfirmationViewController *)viewController;
- (void)shareConfirmationViewControllerDidFinish:(ShareConfirmationViewController *)viewController;

@end

@interface ShareConfirmationViewController : UIViewController

@property (weak, nonatomic) id<ShareConfirmationViewControllerDelegate> delegate;

@property (strong, nonatomic) NCRoom *room;
@property (strong, nonatomic) TalkAccount *account;
@property (strong, nonatomic) ServerCapabilities *serverCapabilities;
@property (assign, nonatomic) ShareConfirmationType type;
@property (strong, nonatomic) NSString *sharedText;
@property (strong, nonatomic) NSString *sharedImageName;
@property (strong, nonatomic) UIImage *sharedImage;


@property (weak, nonatomic) IBOutlet UIView *toBackgroundView;
@property (weak, nonatomic) IBOutlet UITextView *toTextView;
@property (weak, nonatomic) IBOutlet UITextView *shareTextView;
@property (weak, nonatomic) IBOutlet UIImageView *shareImageView;

- (id)initWithRoom:(NCRoom *)room account:(TalkAccount *)account serverCapabilities:(ServerCapabilities *)serverCapabilities;

@end

NS_ASSUME_NONNULL_END
