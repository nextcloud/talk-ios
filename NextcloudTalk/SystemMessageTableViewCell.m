/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "SystemMessageTableViewCell.h"

#import "NCAppBranding.h"

#import "NextcloudTalk-Swift.h"

static CGFloat kChatCellDateLabelWidth      = 40.0;

@interface SystemMessageTableViewCell () <UITextFieldDelegate>
@property (nonatomic, assign) BOOL didCreateSubviews;
@end

@implementation SystemMessageTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor systemGroupedBackgroundColor];
    }
    return self;
}

- (void)configureSubviews
{
    [self.contentView addSubview:self.dateLabel];
    [self.contentView addSubview:self.bodyTextView];
    [self.contentView addSubview:self.collapseButton];

    NSDictionary *views = @{@"dateLabel": self.dateLabel,
                            @"bodyTextView": self.bodyTextView,
                            @"collapseButton" : self.collapseButton
                            };
    
    NSDictionary *metrics = @{@"dateLabelWidth": @(kChatCellDateLabelWidth),
                              @"avatarGap": @50,
                              @"right": @10,
                              @"left": @5
                              };
    
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatarGap-[bodyTextView]-[dateLabel(>=dateLabelWidth)]-right-|" options:0 metrics:metrics views:views]];
    [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-left-[collapseButton(40)]-left-[bodyTextView]-[dateLabel(>=dateLabelWidth)]-right-|" options:NSLayoutFormatAlignAllCenterY metrics:metrics views:views]];
    [self.bodyTextView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor].active = YES;

    self.didCreateSubviews = YES;
}

- (void)prepareForReuse
{
    [super prepareForReuse];

    if (!self.didCreateSubviews) {
        return;
    }
    
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.bodyTextView.text = @"";
    self.dateLabel.text = @"";
}

#pragma mark - Getters

- (MessageBodyTextView *)bodyTextView
{
    if (!_bodyTextView) {
        _bodyTextView = [MessageBodyTextView new];
        _bodyTextView.dataDetectorTypes = UIDataDetectorTypeNone;
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
        _dateLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        _dateLabel.textColor = [UIColor secondaryLabelColor];
    }
    return _dateLabel;
}

- (UIButton *)collapseButton
{
    if (!_collapseButton) {
        _collapseButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 40, 20)];
        _collapseButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_collapseButton addTarget:self action:@selector(collapseButtonPressed) forControlEvents:UIControlEventTouchUpInside];
        [_collapseButton setImage:[UIImage systemImageNamed:@"rectangle.arrowtriangle.2.inward"] forState:UIControlStateNormal];
        _collapseButton.tintColor = [UIColor tertiaryLabelColor];
    }
    return _collapseButton;
}

- (void)collapseButtonPressed
{
    [self.delegate cellWantsToCollapseMessagesWithMessage:self.message];
}

- (void)setupForMessage:(NCChatMessage *)message
{
    self.collapseButton.hidden = (message.isCollapsed || message.collapsedMessages.count == 0);

    // If the message is not visible, we don't need to setup this cell
    if (message.isCollapsed && message.collapsedBy) {
        return;
    }

    if (!self.didCreateSubviews) {
        [self configureSubviews];
    }
    
    self.bodyTextView.attributedText = message.systemMessageFormat;
    self.messageId = message.messageId;
    self.message = message;
    
    if (!message.isGroupMessage && !(message.isCollapsed && message.collapsedBy > 0)) {
        NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:message.timestamp];
        self.dateLabel.text = [NCUtils getTimeFromDate:date];
    }

    if (!message.isCollapsed && (message.collapsedBy > 0 || message.collapsedMessages.count > 0)) {
        self.backgroundColor = [UIColor tertiarySystemFillColor];
    } else {
        self.backgroundColor = [UIColor systemGroupedBackgroundColor];
    }

    if (message.collapsedMessages.count > 0) {
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
}

@end
