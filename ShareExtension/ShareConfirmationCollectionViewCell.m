/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "ShareConfirmationCollectionViewCell.h"

NSString *const kShareConfirmationCellIdentifier = @"ShareConfirmationCellIdentifier";
NSString *const kShareConfirmationTableCellNibName = @"ShareConfirmationCollectionViewCell";

@implementation ShareConfirmationCollectionViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
}


- (void)prepareForReuse
{
    [super prepareForReuse];

    self.previewView.image = nil;
    self.placeholderImageView.image = nil;
    self.placeholderTextView.text = @"";
    
    self.placeholderImageView.hidden = NO;
    self.placeholderTextView.hidden = NO;
}

- (void)setPreviewImage:(UIImage *)image
{
    [self.previewView setImage:image];
    
    self.placeholderImageView.hidden = YES;
    self.placeholderTextView.hidden = YES;
}

- (void)setPlaceHolderImage:(UIImage *)image
{
    [self.placeholderImageView setImage:image];
}

- (void)setPlaceHolderText:(NSString *)text
{
    [self.placeholderTextView setText:text];
}


@end
