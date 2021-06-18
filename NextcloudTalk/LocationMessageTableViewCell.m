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

#import "LocationMessageTableViewCell.h"

#import "MaterialActivityIndicator.h"
#import "SLKUIConstants.h"
#import "UIImageView+AFNetworking.h"
#import "UIImageView+Letters.h"

#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCDatabaseManager.h"
#import "NCUtils.h"

@interface LocationMessageTableViewCell ()
{
    MDCActivityIndicator *_activityIndicator;
    MKMapView *_mapView;
    MKMapSnapshotter *_mapSnapshotter;
}

@end

@implementation LocationMessageTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [NCAppBranding backgroundColor];
        [self configureSubviews];
    }
    return self;
}

- (void)configureSubviews
{
    _avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kLocationMessageCellAvatarHeight, kLocationMessageCellAvatarHeight)];
    _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
    _avatarView.userInteractionEnabled = NO;
    _avatarView.backgroundColor = [NCAppBranding placeholderColor];
    _avatarView.layer.cornerRadius = kLocationMessageCellAvatarHeight/2.0;
    _avatarView.layer.masksToBounds = YES;
    
    _previewImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, kLocationMessageCellPreviewWidth, kLocationMessageCellPreviewHeight)];
    _previewImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _previewImageView.userInteractionEnabled = NO;
    _previewImageView.layer.cornerRadius = 4.0;
    _previewImageView.layer.masksToBounds = YES;
    
    UITapGestureRecognizer *previewTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(previewTapped:)];
    [_previewImageView addGestureRecognizer:previewTap];
    _previewImageView.userInteractionEnabled = YES;
    
    if ([self.reuseIdentifier isEqualToString:LocationMessageCellIdentifier]) {
        [self.contentView addSubview:_avatarView];
        [self.contentView addSubview:self.titleLabel];
        [self.contentView addSubview:self.dateLabel];
    }
    [self.contentView addSubview:_previewImageView];
    [self.contentView addSubview:self.bodyTextView];
    
    _statusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kChatCellStatusViewHeight, kChatCellStatusViewHeight)];
    _statusView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_statusView];
    
    NSDictionary *views = @{@"avatarView": self.avatarView,
                            @"statusView": self.statusView,
                            @"titleLabel": self.titleLabel,
                            @"dateLabel": self.dateLabel,
                            @"previewImageView": self.previewImageView,
                            @"bodyTextView": self.bodyTextView,
                            };
    
    NSDictionary *metrics = @{@"avatarSize": @(kLocationMessageCellAvatarHeight),
                              @"previewWidth": @(kLocationMessageCellPreviewWidth),
                              @"previewHeight": @(kLocationMessageCellPreviewHeight),
                              @"statusSize": @(kChatCellStatusViewHeight),
                              @"padding": @15,
                              @"avatarGap": @50,
                              @"right": @10,
                              @"left": @5
                              };
    
    if ([self.reuseIdentifier isEqualToString:LocationMessageCellIdentifier]) {
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[titleLabel]-[dateLabel(40)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[previewImageView(previewWidth)]-(>=0)-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-right-[avatarView(avatarSize)]-right-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-padding-[statusView(statusSize)]-padding-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[titleLabel(28)]-left-[previewImageView(previewHeight)]-right-[bodyTextView(>=0@999)]-left-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[dateLabel(28)]-left-[previewImageView(previewHeight)]-right-[bodyTextView(>=0@999)]-left-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[avatarView(avatarSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-right-[titleLabel(28)]-left-[previewImageView(previewHeight)]-right-[statusView(statusSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
    } else if ([self.reuseIdentifier isEqualToString:GroupedLocationMessageCellIdentifier]) {
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatarGap-[previewImageView(previewWidth)]-(>=0)-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-avatarGap-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-padding-[statusView(statusSize)]-padding-[bodyTextView(>=0)]-right-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-left-[previewImageView(previewHeight)]-right-[bodyTextView(>=0@999)]-left-|" options:0 metrics:metrics views:views]];
        [self.contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-left-[previewImageView(previewHeight)]-right-[statusView(statusSize)]-(>=0)-|" options:0 metrics:metrics views:views]];
    }
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    CGFloat pointSize = [LocationMessageTableViewCell defaultFontSize];
    
    self.titleLabel.font = [UIFont systemFontOfSize:pointSize];
    self.bodyTextView.font = [UIFont systemFontOfSize:pointSize];
    
    self.titleLabel.text = @"";
    self.bodyTextView.text = @"";
    self.dateLabel.text = @"";
    
    [self.avatarView cancelImageDownloadTask];
    self.avatarView.image = nil;
    
    self.previewImageView.image = nil;
    
    [_mapView removeAnnotations:_mapView.annotations];
    _mapView = nil;
    _mapSnapshotter = nil;
    
    [self.statusView.subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
}

- (void)setupForMessage:(NCChatMessage *)message withLastCommonReadMessage:(NSInteger)lastCommonRead
{
    self.titleLabel.text = message.actorDisplayName;
    self.bodyTextView.attributedText = message.parsedMessage;
    self.messageId = message.messageId;
    
    NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:message.timestamp];
    self.dateLabel.text = [NCUtils getTimeFromDate:date];
    
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [self.avatarView setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:message.actorId andSize:96 usingAccount:activeAccount]
                               placeholderImage:nil success:nil failure:nil];
   
    
    if (message.sendingFailed) {
        UIImageView *errorView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        [errorView setImage:[UIImage imageNamed:@"error"]];
        [self.statusView addSubview:errorView];
    }
    
    self.geoLocationRichObject = [GeoLocationRichObject geoLocationRichObjectFromMessageLocationParameter:message.geoLocation];
    [self createLocationPreview];
    
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    BOOL shouldShowDeliveryStatus = [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityChatReadStatus forAccountId:activeAccount.accountId];
    BOOL shouldShowReadStatus = !serverCapabilities.readStatusPrivacy;
    if ([message.actorId isEqualToString:activeAccount.userId] && [message.actorType isEqualToString:@"users"] && shouldShowDeliveryStatus) {
        if (lastCommonRead >= message.messageId && shouldShowReadStatus) {
            [self setDeliveryState:ChatMessageDeliveryStateRead];
        } else {
            [self setDeliveryState:ChatMessageDeliveryStateSent];
        }
    }
}

- (void)createLocationPreview
{
    _mapView = [[MKMapView alloc] initWithFrame:CGRectMake(0, 0, kLocationMessageCellPreviewWidth, kLocationMessageCellPreviewHeight)];
    MKCoordinateRegion mapRegion;
    mapRegion.center = CLLocationCoordinate2DMake([self.geoLocationRichObject.latitude doubleValue], [self.geoLocationRichObject.longitude doubleValue]);
    mapRegion.span = MKCoordinateSpanMake(0.005, 0.005);
    MKMapSnapshotOptions *options = [[MKMapSnapshotOptions alloc] init];
    options.region = mapRegion;
    options.size = _mapView.frame.size;
    options.scale = [[UIScreen mainScreen] scale];
    _mapSnapshotter = [[MKMapSnapshotter alloc] initWithOptions:options];
    [_mapSnapshotter startWithCompletionHandler:^(MKMapSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        MKPinAnnotationView *pin = [[MKPinAnnotationView alloc] initWithAnnotation:nil reuseIdentifier:nil];
        UIImage *image = snapshot.image;
        UIGraphicsBeginImageContextWithOptions(image.size, YES, image.scale);
        {
            [image drawAtPoint:CGPointMake(0.0f, 0.0f)];

            CGRect rect = CGRectMake(0.0f, 0.0f, image.size.width, image.size.height);
            MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
            annotation.coordinate = CLLocationCoordinate2DMake([self.geoLocationRichObject.latitude doubleValue], [self.geoLocationRichObject.longitude doubleValue]);
            CGPoint point = [snapshot pointForCoordinate:annotation.coordinate];
            if (CGRectContainsPoint(rect, point)) {
                point.x = point.x + pin.centerOffset.x - (pin.bounds.size.width / 2.0f);
                point.y = point.y + pin.centerOffset.y - (pin.bounds.size.height / 2.0f);
                pin.pinTintColor = [NCAppBranding elementColor];
                [pin.image drawAtPoint:point];
            }

            UIImage *compositeImage = UIGraphicsGetImageFromCurrentImageContext();
            [self.previewImageView setImage:compositeImage];
        }
        UIGraphicsEndImageContext();
    }];
}

- (void)setDeliveryState:(ChatMessageDeliveryState)state
{
    [self.statusView.subviews makeObjectsPerformSelector: @selector(removeFromSuperview)];
    
    if (state == ChatMessageDeliveryStateSent) {
        UIImageView *checkView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        [checkView setImage:[UIImage imageNamed:@"check"]];
        checkView.image = [checkView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [checkView setTintColor:[UIColor lightGrayColor]];
        [self.statusView addSubview:checkView];
    } else if (state == ChatMessageDeliveryStateRead) {
        UIImageView *checkAllView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
        [checkAllView setImage:[UIImage imageNamed:@"check-all"]];
        checkAllView.image = [checkAllView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [checkAllView setTintColor:[UIColor lightGrayColor]];
        [self.statusView addSubview:checkAllView];
    }
}

#pragma mark - Getters

- (UILabel *)titleLabel
{
    if (!_titleLabel) {
        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.userInteractionEnabled = NO;
        _titleLabel.numberOfLines = 0;
        _titleLabel.textColor = [UIColor lightGrayColor];
        _titleLabel.font = [UIFont systemFontOfSize:[LocationMessageTableViewCell defaultFontSize]];
        
        if (@available(iOS 13.0, *)) {
            _titleLabel.textColor = [UIColor secondaryLabelColor];
        }
    }
    return _titleLabel;
}

- (UILabel *)dateLabel
{
    if (!_dateLabel) {
        _dateLabel = [UILabel new];
        _dateLabel.textAlignment = NSTextAlignmentRight;
        _dateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _dateLabel.backgroundColor = [UIColor clearColor];
        _dateLabel.userInteractionEnabled = NO;
        _dateLabel.numberOfLines = 0;
        _dateLabel.textColor = [UIColor lightGrayColor];
        _dateLabel.font = [UIFont systemFontOfSize:12.0];
        
        if (@available(iOS 13.0, *)) {
            _dateLabel.textColor = [UIColor secondaryLabelColor];
        }
    }
    return _dateLabel;
}

- (MessageBodyTextView *)bodyTextView
{
    if (!_bodyTextView) {
        _bodyTextView = [MessageBodyTextView new];
        _bodyTextView.font = [UIFont systemFontOfSize:[LocationMessageTableViewCell defaultFontSize]];
        _bodyTextView.dataDetectorTypes = UIDataDetectorTypeNone;
    }
    return _bodyTextView;
}

- (void)previewTapped:(UITapGestureRecognizer *)recognizer
{
    if (!self.geoLocationRichObject) {
        return;
    }
    
    if (self.delegate) {
        [self.delegate cellWantsToOpenLocation:self.geoLocationRichObject];
    }
}

- (void)setGuestAvatar:(NSString *)displayName
{
    UIColor *guestAvatarColor = [NCAppBranding placeholderColor];
    NSString *name = ([displayName isEqualToString:@""]) ? @"?" : displayName;
    [_avatarView setImageWithString:name color:guestAvatarColor circular:true];
}

+ (CGFloat)defaultFontSize
{
    CGFloat pointSize = 16.0;
    
    //    NSString *contentSizeCategory = [[UIApplication sharedApplication] preferredContentSizeCategory];
    //    pointSize += SLKPointSizeDifferenceForCategory(contentSizeCategory);
    
    return pointSize;
}

@end
