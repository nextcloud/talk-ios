//
//  DateHeaderView.m
//  VideoCalls
//
//  Created by Ivan Sein on 16.05.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "DateHeaderView.h"

@interface DateHeaderView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;

@end

@implementation DateHeaderView

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:@"DateHeaderView" owner:self options:nil];
        
        [self addSubview:self.contentView];
        
        self.contentView.frame = self.bounds;
    }
    
    return self;
}

@end
