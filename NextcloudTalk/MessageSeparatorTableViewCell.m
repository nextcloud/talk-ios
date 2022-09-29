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

#import "MessageSeparatorTableViewCell.h"

@implementation MessageSeparatorTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor secondarySystemBackgroundColor];

        [self configureSubviews];
    }
    return self;
}

- (void)configureSubviews
{
    [self.contentView addSubview:self.separatorLabel];
    
    NSDictionary *views = @{@"separatorLabel": self.separatorLabel};
    
    NSDictionary *metrics = @{@"left": @10,
                              @"top": @5
                              };
    
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-left-[separatorLabel(>=0)]-left-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-top-[separatorLabel(14)]-top-|" options:0 metrics:metrics views:views]];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.separatorLabel.text = @"";
    self.selectionStyle = UITableViewCellSelectionStyleNone;
}

#pragma mark - Getters

- (UILabel *)separatorLabel
{
    if (!_separatorLabel) {
        _separatorLabel = [UILabel new];
        _separatorLabel.textAlignment = NSTextAlignmentCenter;
        _separatorLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _separatorLabel.backgroundColor = [UIColor clearColor];
        _separatorLabel.userInteractionEnabled = NO;
        _separatorLabel.numberOfLines = 1;
        _separatorLabel.font = [UIFont systemFontOfSize:12.0];
        _separatorLabel.text = NSLocalizedString(@"Unread messages", nil);
        _separatorLabel.textColor = [UIColor secondaryLabelColor];
    }
    return _separatorLabel;
}

@end
