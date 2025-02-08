/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class Mention;

@interface NCMessageParameter : NSObject

@property (nonatomic, strong) NSString *parameterId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString * _Nullable link;
@property (nonatomic, strong) NSString *type;
@property (nonatomic, assign) NSRange range;
@property (nonatomic, strong) NSString *contactName;
@property (nonatomic, strong) NSString *contactPhoto;
@property (nonatomic, strong) Mention * _Nullable mention;

- (instancetype)initWithDictionary:(NSDictionary *)parameterDict;
- (BOOL)shouldBeHighlighted;
- (UIImage * _Nullable)contactPhotoImage;
- (BOOL)isMention;

// parametersDict as [NSString:NCMessageParameter]
+ (NSString *)messageParametersJSONStringFromDictionary:(NSDictionary *)parametersDict;
+ (NSDictionary<NSString *, NCMessageParameter *> *)messageParametersDictFromJSONString:(NSString *)parametersJSONString;

@end
