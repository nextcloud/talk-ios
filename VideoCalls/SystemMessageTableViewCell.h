//
//  SystemMessageTableViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 07.08.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "ChatTableViewCell.h"

static CGFloat kSystemMessageCellMinimumHeight  = 30.0;

static NSString *SystemMessageCellIdentifier    = @"SystemMessageCellIdentifier";

@interface SystemMessageTableViewCell : ChatTableViewCell

@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *bodyLabel;

+ (CGFloat)defaultFontSize;

@end
