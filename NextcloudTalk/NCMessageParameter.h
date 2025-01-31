/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface NCMessageParameter : NSObject

@property (nonatomic, strong) NSString *parameterId;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString * _Nullable link;
@property (nonatomic, strong) NSString *type;
@property (nonatomic, assign) NSRange range;
@property (nonatomic, strong) NSString *contactName;
@property (nonatomic, strong) NSString *contactPhoto;
// Helper property for mentions created using the app
@property (nonatomic, strong) NSString * _Nullable mentionId;
@property (nonatomic, strong) NSString *mentionDisplayName;

- (instancetype)initWithDictionary:(NSDictionary *)parameterDict;
- (BOOL)shouldBeHighlighted;
- (UIImage * _Nullable)contactPhotoImage;

// parametersDict as [NSString:NCMessageParameter]
+ (NSString *)messageParametersJSONStringFromDictionary:(NSDictionary *)parametersDict;
+ (NSDictionary<NSString *, NCMessageParameter *> *)messageParametersDictFromJSONString:(NSString *)parametersJSONString;

@end
