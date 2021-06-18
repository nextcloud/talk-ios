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

#import "NCMessageParameter.h"

#import "NCDatabaseManager.h"

@implementation NCMessageParameter

- (instancetype)initWithDictionary:(NSDictionary *)parameterDict
{
    self = [super init];
    if (self) {
        if (!parameterDict || ![parameterDict isKindOfClass:[NSDictionary class]]) {
            return nil;
        }
        
        self.parameterId = [parameterDict objectForKey:@"id"];
        self.name = [parameterDict objectForKey:@"name"];
        self.link = [parameterDict objectForKey:@"link"];
        self.type = [parameterDict objectForKey:@"type"];
        
        id parameterId = [parameterDict objectForKey:@"id"];
        if ([parameterId isKindOfClass:[NSString class]]) {
            self.parameterId = parameterId;
        } else {
            self.parameterId = [parameterId stringValue];
        }
        
        self.contactName = [parameterDict objectForKey:@"contact-name"];
        self.contactPhoto = [parameterDict objectForKey:@"contact-photo"];
    }
    
    return self;
}

- (BOOL)shouldBeHighlighted
{
    // Own mentions
    // Call mentions
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    return ([_type isEqualToString:@"user"] && [activeAccount.userId isEqualToString:_parameterId]) || [_type isEqualToString:@"call"];
}

- (UIImage *)contactPhotoImage
{
    if (self.contactPhoto) {
        NSString *base64String = [NSString stringWithFormat:@"%@%@", @"data:image/png;base64,", self.contactPhoto];
        NSURL *url = [NSURL URLWithString:base64String];
        NSData *imageData = [NSData dataWithContentsOfURL:url];
        return [UIImage imageWithData:imageData];
    }
    
    return nil;
}

@end
