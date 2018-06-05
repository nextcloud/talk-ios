//
//  ChatPlaceholderView.h
//  VideoCalls
//
//  Created by Ivan Sein on 25.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ChatPlaceholderView : UIView

@property (weak, nonatomic) IBOutlet UIView *placeholderView;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *loadingView;

@end
