//
//  UnreadMessagesView.m
//  VideoCalls
//
//  Created by Ivan Sein on 04.06.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "UnreadMessagesView.h"

@interface UnreadMessagesView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;
@property (weak, nonatomic) IBOutlet UILabel *unreadMessagesLabel;

@end

@implementation UnreadMessagesView

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:@"UnreadMessagesView" owner:self options:nil];
        
        [self addSubview:self.contentView];
        self.contentView.frame = self.bounds;
        
        self.unreadMessagesLabel.layer.cornerRadius = 12.0f;
        self.unreadMessagesLabel.clipsToBounds = YES;
    }
    
    return self;
}

@end
