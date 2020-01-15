//
//  RoomTableViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 19.07.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString *const kRoomCellIdentifier;
extern NSString *const kRoomTableCellNibName;

extern CGFloat const kRoomTableCellHeight;

@interface RoomTableViewCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UIImageView *roomImage;
@property (nonatomic, weak) IBOutlet UILabel *titleLabel;
@property (nonatomic, weak) IBOutlet UILabel *subtitleLabel;
@property (nonatomic, weak) IBOutlet UIView *unreadMessagesView;
@property (nonatomic, weak) IBOutlet UILabel *dateLabel;
@property (weak, nonatomic) IBOutlet UIImageView *favoriteImage;

@property (nonatomic, assign) BOOL titleOnly;

- (void)setUnreadMessages:(NSInteger)number mentioned:(BOOL)mentioned;

@end
