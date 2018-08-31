//
//  NCFilePreviewSessionManager.h
//  VideoCalls
//
//  Created by Ivan Sein on 28.08.18.
//  Copyright © 2018 struktur AG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AFNetworking.h"

typedef void (^GetFilePreviewCompletionBlock)(UIImage *preview, NSError *error);

@interface NCFilePreviewSessionManager : AFHTTPSessionManager

@property (nonatomic, strong) NSString *userAgent;

+ (instancetype)sharedInstance;
- (void)setNCServer:(NSString *)serverUrl;
- (void)setAuthHeaderWithUser:(NSString *)user andToken:(NSString *)token;
- (NSURLSessionDataTask *)getFilePreview:(NSString *)fileId width:(NSInteger)width height:(NSInteger)height withCompletionBlock:(GetFilePreviewCompletionBlock)block;
- (NSURLRequest *)createPreviewRequestForFile:(NSString *)fileId width:(NSInteger)width height:(NSInteger)height;

@end

