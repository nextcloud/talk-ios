//
//  DirectoryTableViewCell.h
//  VideoCalls
//
//  Created by Ivan Sein on 23.04.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kDirectoryCellIdentifier;
extern NSString *const kDirectoryTableCellNibName;

extern CGFloat const kDirectoryTableCellHeight;

@interface DirectoryTableViewCell : UITableViewCell

@property (weak, nonatomic) IBOutlet UIImageView *fileImageView;
@property (weak, nonatomic) IBOutlet UILabel *fileNameLabel;
@property (weak, nonatomic) IBOutlet UILabel *fileInfoLabel;

@end

NS_ASSUME_NONNULL_END
