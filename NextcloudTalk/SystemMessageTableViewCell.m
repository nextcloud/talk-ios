/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "SystemMessageTableViewCell.h"

#import "NCAppBranding.h"
#import "NCUtils.h"

@implementation SystemMessageTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [NCAppBranding backgroundColor];
        
        [self configureSubviews];
    }
    return self;
}

- (void)configureSubviews
{
    if ([self.reuseIdentifier isEqualToString:InvisibleSystemMessageCellIdentifier]) {
        return;
    }
    
    [self.contentView addSubview:self.dateLabel];
    [self.contentView addSubview:self.bodyTextView];
    
    NSDictionary *views = @{@"dateLabel": self.dateLabel,
                            @"bodyTextView": self.bodyTextView,
                            };
    
    NSDictionary *metrics = @{@"dateLabelWidth": @(kChatCellDateLabelWidth),
                              @"avatarGap": @50,
                              @"right": @10,
                              @"left": @5
                              };
    
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatarGap-[bodyTextView]-[dateLabel(>=dateLabelWidth)]-right-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-left-[bodyTextView(>=0@999)]-left-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-left-[dateLabel(20)]-(>=0)-|" options:0 metrics:metrics views:views]];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    CGFloat pointSize = [SystemMessageTableViewCell defaultFontSize];
    self.bodyTextView.font = [UIFont systemFontOfSize:pointSize];
    self.bodyTextView.text = @"";
    self.dateLabel.text = @"";
}

#pragma mark - Getters

- (MessageBodyTextView *)bodyTextView
{
    if (!_bodyTextView) {
        _bodyTextView = [MessageBodyTextView new];
        _bodyTextView.font = [UIFont systemFontOfSize:[SystemMessageTableViewCell defaultFontSize]];
    }
    return _bodyTextView;
}

- (UILabel *)dateLabel
{
    if (!_dateLabel) {
        _dateLabel = [UILabel new];
        _dateLabel.textAlignment = NSTextAlignmentRight;
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _dateLabel.backgroundColor = [UIColor clearColor];
        _dateLabel.userInteractionEnabled = NO;
        _dateLabel.numberOfLines = 1;
        _dateLabel.font = [UIFont systemFontOfSize:12.0];
        _dateLabel.textColor = [UIColor secondaryLabelColor];
    }
    return _dateLabel;
}

+ (CGFloat)defaultFontSize
{
    CGFloat pointSize = 16.0;
    
    //    NSString *contentSizeCategory = [[UIApplication sharedApplication] preferredContentSizeCategory];
    //    pointSize += SLKPointSizeDifferenceForCategory(contentSizeCategory);
    
    return pointSize;
}

- (void)setupForMessage:(NCChatMessage *)message
{
    self.bodyTextView.attributedText = message.systemMessageFormat;
    self.messageId = message.messageId;
    self.message = message;
    
    if (!message.isGroupMessage) {
        NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:message.timestamp];
        self.dateLabel.text = [NCUtils getTimeFromDate:date];
    }
}

@end
