//
//  ChatPlaceholderView.m
//  VideoCalls
//
//  Created by Ivan Sein on 25.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "ChatPlaceholderView.h"

@interface ChatPlaceholderView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;

@end

@implementation ChatPlaceholderView

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:@"ChatPlaceholderView" owner:self options:nil];
        
        [self addSubview:self.contentView];
        
        self.contentView.frame = self.bounds;
    }
    
    return self;
}

@end
