//
//  ShareTableViewCell.m
//  ShareExtension
//
//  Created by Ivan Sein on 20.07.20.
//  Copyright © 2020 struktur AG. All rights reserved.
//

#import "ShareTableViewCell.h"

#import "AFNetworking.h"
#import "AFImageDownloader.h"
#import "NCImageSessionManager.h"
#import "UIImageView+AFNetworking.h"

NSString *const kShareCellIdentifier = @"ShareCellIdentifier";
NSString *const kShareTableCellNibName = @"ShareTableViewCell";

CGFloat const kShareTableCellHeight = 56.0f;

@implementation ShareAvatarImageView : UIImageView
@end

@implementation ShareTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    
    self.avatarImageView.layer.cornerRadius = 18.0;
    self.avatarImageView.layer.masksToBounds = YES;
    
    AFImageDownloader *imageDownloader = [[AFImageDownloader alloc]
                                          initWithSessionManager:[NCImageSessionManager sharedInstance]
                                          downloadPrioritization:AFImageDownloadPrioritizationFIFO
                                          maximumActiveDownloads:4
                                          imageCache:[[AFAutoPurgingImageCache alloc] init]];
    [ShareAvatarImageView setSharedImageDownloader:imageDownloader];
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    // Fix problem of rendering downloaded image in a reused cell
    [self.avatarImageView cancelImageDownloadTask];
    
    self.avatarImageView.image = nil;
    self.titleLabel.text = @"";
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
