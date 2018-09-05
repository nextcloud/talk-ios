//
//  PlaceholderView.m
//  VideoCalls
//
//  Created by Ivan Sein on 25.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "PlaceholderView.h"

@interface PlaceholderView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;

@end

@implementation PlaceholderView

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:@"PlaceholderView" owner:self options:nil];
        
        [self addSubview:self.contentView];
        
        self.contentView.frame = self.bounds;
    }
    
    return self;
}

@end
