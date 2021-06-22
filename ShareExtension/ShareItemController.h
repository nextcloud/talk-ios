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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "ShareItem.h"

NS_ASSUME_NONNULL_BEGIN

@class ShareItemController;
@protocol ShareItemControllerDelegate <NSObject>

- (void)shareItemControllerItemsChanged:(ShareItemController *)shareItemController;

@end


@interface ShareItemController : NSObject

@property (nonatomic, weak) id<ShareItemControllerDelegate> delegate;
@property (strong, nonatomic) NSMutableArray *shareItems;

- (void)addItemWithURL:(NSURL *)fileURL;
- (void)addItemWithURLAndName:(NSURL *)fileURL withName:(NSString *)fileName;
- (void)addItemWithImage:(UIImage *)image;
- (void)addItemWithImageAndName:(UIImage *)image withName:(NSString *)imageName;
- (void)addItemWithContactData:(NSData *)data;
- (void)addItemWithContactDataAndName:(NSData *)data withName:(NSString *)imageName;
- (void)updateItem:(ShareItem *)item withImage:(UIImage *)image;
- (void)updateItem:(ShareItem *)item withURL:(NSURL *)fileURL;
- (void)removeItem:(ShareItem *)item;
- (void)removeAllItems;
- (UIImage *)getImageFromItem:(ShareItem *)item;

@end

NS_ASSUME_NONNULL_END
