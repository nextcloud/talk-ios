/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>

#import "NCDatabaseManager.h"
#import "NCMessageFileParameter.h"

@class NCChatFileStatus;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const NCChatFileControllerDidChangeIsDownloadingNotification;
extern NSString * const NCChatFileControllerDidChangeDownloadProgressNotification;

@class NCChatFileController;

@protocol NCChatFileControllerDelegate<NSObject>

- (void)fileControllerDidLoadFile:(NCChatFileController *)fileController withFileStatus:(NCChatFileStatus *)fileStatus;
- (void)fileControllerDidFailLoadingFile:(NCChatFileController *)fileController withErrorDescription:(NSString *)errorDescription;

@end

@interface NCChatFileController : NSObject

@property (nonatomic, weak) id<NCChatFileControllerDelegate> delegate;
@property (nonatomic, strong) NSString *messageType;
@property (nonatomic, strong) NSString *actionType;

- (void)downloadFileFromMessage:(NCMessageFileParameter *)fileParameter;
- (void)downloadFileWithFileId:(NSString *)fileId;
- (void)deleteDownloadDirectoryForAccount:(TalkAccount *)account;
- (void)clearDownloadDirectoryForAccount:(TalkAccount *)account;
- (NSInteger)getDiskUsageForAccount:(TalkAccount *)account;

@end

NS_ASSUME_NONNULL_END
