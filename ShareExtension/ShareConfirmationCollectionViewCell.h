/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */


#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kShareConfirmationCellIdentifier;
extern NSString *const kShareConfirmationTableCellNibName;

@interface ShareConfirmationCollectionViewCell : UICollectionViewCell

@property (strong, nonatomic) IBOutlet UIImageView *previewView;
@property (strong, nonatomic) IBOutlet UIImageView *placeholderImageView;
@property (strong, nonatomic) IBOutlet UITextView *placeholderTextView;

- (void)setPlaceHolderImage:(UIImage *)image;
- (void)setPlaceHolderText:(NSString *)text;
- (void)setPreviewImage:(UIImage *)image;

@end

NS_ASSUME_NONNULL_END
