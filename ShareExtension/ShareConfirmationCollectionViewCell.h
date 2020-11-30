/**
 * @copyright Copyright (c) 2020 Marcel Müller <marcel-mueller@gmx.de>
 *
 * @author Marcel Müller <marcel-mueller@gmx.de>
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
