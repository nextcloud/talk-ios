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

#import "NCDatabaseManager.h"
#import "NCMessageFileParameter.h"
#import "NCChatFileStatus.h"

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

@end

NS_ASSUME_NONNULL_END
