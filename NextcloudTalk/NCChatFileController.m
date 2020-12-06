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

#import "NCChatFileController.h"
#import "NCDatabaseManager.h"
#import "NCSettingsController.h"
#import "NCAPIController.h"

NSString * const NCChatFileControllerDidChangeIsDownloadingNotification     = @"NCChatFileControllerDidChangeIsDownloadingNotification";
NSString * const NCChatFileControllerDidChangeDownloadProgressNotification  = @"NCChatFileControllerDidChangeDownloadProgressNotification";

int const kNCChatFileControllerDeleteFilesOlderThanDays = 7;

@interface NCChatFileController ()

@property (nonatomic, strong) TalkAccount *account;
@property (nonatomic, strong) NCMessageFileParameter *fileParameter;
@property (nonatomic, strong) NSString *tempDirectoryPath;
@property (nonatomic, strong) NSString *fileLocalPath;

@end


@implementation NCChatFileController

- (void)initDownloadDirectoryForAccount:(TalkAccount *)account
{
    _account = account;
    
    NSString *encodedAccountId = [account.accountId stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLHostAllowedCharacterSet];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    _tempDirectoryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"/download/"];
    _tempDirectoryPath = [_tempDirectoryPath stringByAppendingPathComponent:encodedAccountId];
    
    NSLog(@"Directory for downloads: %@", _tempDirectoryPath);
    
    if (![fileManager fileExistsAtPath:_tempDirectoryPath]) {
        // Make sure our download directory exists
        [fileManager createDirectoryAtPath:_tempDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    [self removeOldFilesFromCache:kNCChatFileControllerDeleteFilesOlderThanDays];
}

- (void)removeOldFilesFromCache:(int)thresholdDays
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtPath:_tempDirectoryPath];
    
    NSDateComponents *dayComponent = [[NSDateComponents alloc] init];
    dayComponent.day = -thresholdDays;

    NSDate *thresholdDate = [[NSCalendar currentCalendar] dateByAddingComponents:dayComponent toDate:[NSDate date] options:0];
    NSString *file;
    
    while (file = [enumerator nextObject])
    {
        NSString *filePath = [_tempDirectoryPath stringByAppendingPathComponent:file];
        NSDate *creationDate = [[fileManager attributesOfItemAtPath:filePath error:nil] fileCreationDate];
        
        if ([creationDate compare:thresholdDate] == NSOrderedAscending) {
            NSLog(@"Deleting file from cache: %@", filePath);
        
            [fileManager removeItemAtPath:filePath error:nil];
        }
    }
}

- (void)deleteDownloadDirectoryForAccount:(TalkAccount *)account
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    [self initDownloadDirectoryForAccount:account];
    [fileManager removeItemAtPath:_tempDirectoryPath error:nil];
    
    NSLog(@"Deleted download directory: %@", _tempDirectoryPath);
}

- (BOOL)isFileInCache:(NSString *)filePath withModificationDate:(NSDate *)date withSize:(double)size
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:filePath]) {
        return NO;
    }
    
    NSError *error = nil;
    NSDictionary<NSFileAttributeKey, id> *fileAttributes = [fileManager attributesOfItemAtPath:filePath error:&error];
    
    NSDate *modificationDate = [fileAttributes fileModificationDate];
    long long fileSize = [fileAttributes fileSize];
    
    if ([date compare:modificationDate] == NSOrderedSame && fileSize == (long long)size) {
        return YES;
    }
    
    // At this point there's a file in our cache but there's a newer one available
    NSLog(@"Deleting file from cache: %@", filePath);
    [fileManager removeItemAtPath:filePath error:nil];
    
    return NO;
}

- (void)setModificationDateOnFile:(NSString *)filePath withModificationDate:(NSDate *)date
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSDictionary *modificationDateAttr = [NSDictionary dictionaryWithObjectsAndKeys:date, NSFileModificationDate, nil];
    [fileManager setAttributes:modificationDateAttr ofItemAtPath:filePath error:nil];
}

- (void)downloadFileFromMessage:(NCMessageFileParameter *)fileParameter
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    ServerCapabilities *serverCapabilities = [[NCDatabaseManager sharedInstance] serverCapabilitiesForAccountId:activeAccount.accountId];
    
    [[NCAPIController sharedInstance] setupNCCommunicationForAccount:activeAccount];
    [self initDownloadDirectoryForAccount:activeAccount];
    
    NSString *serverUrlFileName = [NSString stringWithFormat:@"%@/%@/%@", activeAccount.server, serverCapabilities.webDAVRoot, fileParameter.path];
    _account = activeAccount;
    _fileParameter = fileParameter;
    _fileLocalPath = [_tempDirectoryPath stringByAppendingPathComponent:fileParameter.name];
    
    // Setting just isDownloading without a concrete progress will show an indeterminate activity indicator
    [self didChangeIsDownloadingNotification:YES];
    
    // First read metadata from the file and check if we already downloaded it
    [[NCCommunication shared] readFileOrFolderWithServerUrlFileName:serverUrlFileName depth:@"0" showHiddenFiles:NO requestBody:nil customUserAgent:nil addCustomHeaders:nil completionHandler:^(NSString *accounts, NSArray<NCCommunicationFile *> *files, NSData *responseData, NSInteger errorCode, NSString *errorDescription) {
        if (errorCode == 0 && files.count == 1) {
            // File exists on server -> check our cache
            NCCommunicationFile *file = files.firstObject;
            
            if ([self isFileInCache:self->_fileLocalPath withModificationDate:file.date withSize:file.size]) {
                NSLog(@"Found file in cache: %@", self->_fileLocalPath);
                
                [self didChangeIsDownloadingNotification:NO];
                [self.delegate fileControllerDidLoadFile:self withFileParameter:self->_fileParameter withFilePath:self->_fileLocalPath];
                
                return;
            }

            [[NCCommunication shared] downloadWithServerUrlFileName:serverUrlFileName fileNameLocalPath:self->_fileLocalPath customUserAgent:nil addCustomHeaders:nil progressHandler:^(NSProgress *progress) {
                [self didChangeDownloadProgressNotification:progress.fractionCompleted];
            } completionHandler:^(NSString *account, NSString *etag, NSDate *date, double length, NSDictionary *allHeaderFields, NSInteger errorCode, NSString * errorDescription) {
                [self setModificationDateOnFile:self->_fileLocalPath withModificationDate:file.date];
                [self didChangeIsDownloadingNotification:NO];
                [self.delegate fileControllerDidLoadFile:self withFileParameter:self->_fileParameter withFilePath:self->_fileLocalPath];
            }];
        } else {
            [self didChangeIsDownloadingNotification:NO];
            NSLog(@"Error reading file: %ld", errorCode);
        }
    }];
}

- (void)didChangeIsDownloadingNotification:(BOOL)isDownloading
{
    _fileParameter.isDownloading = NO;
    
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_account forKey:@"account"];
    [userInfo setObject:_fileParameter forKey:@"fileParameter"];
    [userInfo setObject:@(isDownloading) forKey:@"isDownloading"];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:NCChatFileControllerDidChangeIsDownloadingNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)didChangeDownloadProgressNotification:(double)progress
{
    _fileParameter.downloadProgress = progress;
    
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_account forKey:@"account"];
    [userInfo setObject:_fileParameter forKey:@"fileParameter"];
    [userInfo setObject:@(progress) forKey:@"progress"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NCChatFileControllerDidChangeDownloadProgressNotification
                                                        object:self
                                                      userInfo:userInfo];
}

@end
