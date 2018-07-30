//
//  HeaderWithButton.m
//  VideoCalls
//
//  Created by Ivan Sein on 30.07.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "HeaderWithButton.h"

@interface HeaderWithButton ()

@property (strong, nonatomic) IBOutlet UIView *contentView;

@end

@implementation HeaderWithButton

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:@"HeaderWithButton" owner:self options:nil];
        
        [self addSubview:self.contentView];
        
        self.contentView.frame = self.bounds;
    }
    
    return self;
}

@end
