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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface NCMessageParameter : NSObject

@property (nonatomic, strong) NSString *parameterId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *link;
@property (nonatomic, strong) NSString *type;
@property (nonatomic, assign) NSRange range;
@property (nonatomic, strong) NSString *contactName;
@property (nonatomic, strong) NSString *contactPhoto;
// Helper property for mentions created using the app
@property (nonatomic, strong) NSString *mentionId;
@property (nonatomic, strong) NSString *mentionDisplayName;

- (instancetype)initWithDictionary:(NSDictionary *)parameterDict;
- (BOOL)shouldBeHighlighted;
- (UIImage *)contactPhotoImage;

// parametersDict as [NSString:NCMessageParameter]
+ (NSString *)messageParametersJSONStringFromDictionary:(NSDictionary *)parametersDict;
+ (NSDictionary *)messageParametersDictFromJSONString:(NSString *)parametersJSONString;

@end
