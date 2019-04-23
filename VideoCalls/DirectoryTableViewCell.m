//
//  DirectoryTableViewCell.m
//  VideoCalls
//
//  Created by Ivan Sein on 23.04.19.
//  Copyright © 2019 struktur AG. All rights reserved.
//

#import "DirectoryTableViewCell.h"

#import "UIImageView+AFNetworking.h"

NSString *const kDirectoryCellIdentifier = @"DirectoryCellIdentifier";
NSString *const kDirectoryTableCellNibName = @"DirectoryTableViewCell";

CGFloat const kDirectoryTableCellHeight = 60.0f;

@implementation DirectoryTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    // Fix problem of rendering downloaded image in a reused cell
    [self.fileImageView cancelImageDownloadTask];
    
    self.fileImageView.image = nil;
    self.fileNameLabel.text = @"";
    self.fileInfoLabel.text = @"";
}

@end
