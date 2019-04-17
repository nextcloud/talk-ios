//
//  NCMessageTextView.m
//  VideoCalls
//
//  Created by Ivan Sein on 24.04.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCMessageTextView.h"

@implementation NCMessageTextView

- (instancetype)init
{
    if (self = [super init]) {
        // Do something
    }
    return self;
}

- (void)willMoveToSuperview:(UIView *)newSuperview
{
    [super willMoveToSuperview:newSuperview];
    
    self.keyboardType = UIKeyboardTypeDefault;
    
    self.backgroundColor = [UIColor whiteColor];
    
    self.placeholder = NSLocalizedString(@"New message …", nil);
    self.placeholderColor = [UIColor lightGrayColor];
    
    self.layer.borderColor = [UIColor lightGrayColor].CGColor;
}

@end
