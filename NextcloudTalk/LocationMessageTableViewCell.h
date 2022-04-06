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

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import "ChatTableViewCell.h"
#import "GeoLocationRichObject.h"
#import "MessageBodyTextView.h"
#import "NCChatMessage.h"

static CGFloat kLocationMessageCellMinimumHeight    = 50.0;
static CGFloat kLocationMessageCellPreviewWidth     = 240.0;
static CGFloat kLocationMessageCellPreviewHeight    = 120.0;

static NSString *LocationMessageCellIdentifier          = @"LocationMessageCellIdentifier";
static NSString *GroupedLocationMessageCellIdentifier   = @"GroupedLocationMessageCellIdentifier";

@class LocationMessageTableViewCell;

@protocol LocationMessageTableViewCellDelegate <ChatTableViewCellDelegate>

- (void)cellWantsToOpenLocation:(GeoLocationRichObject *)geoLocationRichObject;

@end

@interface LocationMessageTableViewCell : ChatTableViewCell <ReactionsViewDelegate>

@property (nonatomic, weak) id<LocationMessageTableViewCellDelegate> delegate;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIImageView *previewImageView;
@property (nonatomic, strong) MessageBodyTextView *bodyTextView;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UIView *statusView;
@property (nonatomic, strong) GeoLocationRichObject *geoLocationRichObject;
@property (nonatomic, strong) ReactionsView *reactionsView;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *vConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *vGroupedConstraints;

+ (CGFloat)defaultFontSize;
- (void)setGuestAvatar:(NSString *)displayName;
- (void)setupForMessage:(NCChatMessage *)message withLastCommonReadMessage:(NSInteger)lastCommonRead;

@end
