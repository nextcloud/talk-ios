//
//  NCChatTitleView.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.07.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import "NCChatTitleView.h"

@interface NCChatTitleView ()

@property (strong, nonatomic) IBOutlet UIView *contentView;

@end

@implementation NCChatTitleView

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:@"NCChatTitleView" owner:self options:nil];
        
        [self addSubview:self.contentView];
        
        self.contentView.frame = self.bounds;
        self.image.layer.cornerRadius = 15.0f;
        self.image.clipsToBounds = YES;
        self.title.titleLabel.adjustsFontSizeToFitWidth = YES;
        self.title.titleLabel.minimumScaleFactor = 0.75;
    }
    
    return self;
}

@end
