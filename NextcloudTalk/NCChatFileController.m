/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "NCChatFileController.h"

@import NextcloudKit;

#import "NCAPIController.h"
#import "NCDatabaseManager.h"

#import "NextcloudTalk-Swift.h"

NSString * const NCChatFileControllerDidChangeIsDownloadingNotification     = @"NCChatFileControllerDidChangeIsDownloadingNotification";
NSString * const NCChatFileControllerDidChangeDownloadProgressNotification  = @"NCChatFileControllerDidChangeDownloadProgressNotification";

int const kNCChatFileControllerDeleteFilesOlderThanDays = 7;

@interface NCChatFileController ()

@property (nonatomic, strong) NCChatFileStatus *fileStatus;

@end


@implementation NCChatFileController

- (void)initDownloadDirectoryForAccount:(TalkAccount *)account
{
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

- (void)clearDownloadDirectoryForAccount:(TalkAccount *)account
{
    [self deleteDownloadDirectoryForAccount:account];
    [self initDownloadDirectoryForAccount:account];
}

- (NSInteger)getDiskUsageForAccount:(TalkAccount *)account
{
    [self initDownloadDirectoryForAccount:account];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtPath:_tempDirectoryPath];

    NSString *file;
    NSInteger folderSize = 0;

    while (file = [enumerator nextObject])
    {
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[_tempDirectoryPath stringByAppendingPathComponent:file] error:nil];
        folderSize += [[fileAttributes objectForKey:NSFileSize] intValue];
    }

    return folderSize;
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
    
    // At this point there's a file in our cache but there's a different one on the server
    NSLog(@"Deleting file from cache: %@", filePath);
    [fileManager removeItemAtPath:filePath error:nil];
    
    return NO;
}

- (void)setCreationDateOnFile:(NSString *)filePath withCreationDate:(NSDate *)date
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSDictionary *creationDateAttr = [NSDictionary dictionaryWithObjectsAndKeys:date, NSFileCreationDate, nil];
    [fileManager setAttributes:creationDateAttr ofItemAtPath:filePath error:nil];
}

- (void)setModificationDateOnFile:(NSString *)filePath withModificationDate:(NSDate *)date
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSDictionary *modificationDateAttr = [NSDictionary dictionaryWithObjectsAndKeys:date, NSFileModificationDate, nil];
    [fileManager setAttributes:modificationDateAttr ofItemAtPath:filePath error:nil];
}

- (void)downloadFileFromMessage:(NCMessageFileParameter *)fileParameter
{
    _fileStatus = [[NCChatFileStatus alloc] initWithFileId:fileParameter.parameterId fileName:fileParameter.name filePath:fileParameter.path fileLocalPath: nil];
    fileParameter.fileStatus = _fileStatus;
    
    [self startDownload];
}

- (void)downloadFileWithFileId:(NSString *)fileId
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];

    [[NCAPIController sharedInstance] getFileByIdForAccount:activeAccount withFileId:fileId completionBlock:^(NKFile * _Nullable file, NKError * _Nullable error) {
        if (file) {
            NSString *remoteDavPrefix = [NSString stringWithFormat:@"/remote.php/dav/files/%@/", activeAccount.userId];
            NSString *directoryPath = [file.path componentsSeparatedByString:remoteDavPrefix].lastObject;

            NSString *filePath = [NSString stringWithFormat:@"%@%@", directoryPath, file.fileName];

            self->_fileStatus = [[NCChatFileStatus alloc] initWithFileId:file.fileId fileName:file.fileName filePath:filePath fileLocalPath:nil];
            [self startDownload];
        } else {
            NSLog(@"An error occurred while getting file with fileId %@: %@", fileId, error.errorDescription);
            [self.delegate fileControllerDidFailLoadingFile:self withFileId:fileId withErrorDescription:error.errorDescription];
        }
    }];
}

- (bool)moveFileToTemporaryDirectoryFromSourcePath:(NSString *)sourcePath destinationPath:(NSString *)destinationPath {
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    [self initDownloadDirectoryForAccount:activeAccount];

    if (!sourcePath || !destinationPath) {
        NSLog(@"Missing file information. File could not be moved.");
        return false;
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:destinationPath]) {
        NSLog(@"File is already in temporary directory: %@", destinationPath);
        return false;
    }

    NSError *error = nil;
    if ([[NSFileManager defaultManager] moveItemAtPath:sourcePath toPath:destinationPath error:&error]) {
        NSLog(@"File successfully moved to: %@", destinationPath);
        return true;
    } else {
        NSLog(@"Error while moving file to temporary directory: %@", error.localizedDescription);
    }

    return false;
}

- (void)startDownload
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    
    [[NCAPIController sharedInstance] setupNCCommunicationForAccount:activeAccount];
    [self initDownloadDirectoryForAccount:activeAccount];
    
    NSString *serverUrlFileName = [NSString stringWithFormat:@"%@%@/%@", activeAccount.server, [[NCAPIController sharedInstance] filesPathForAccount:activeAccount], _fileStatus.filePath];
    _fileStatus.fileLocalPath = [_tempDirectoryPath stringByAppendingPathComponent:_fileStatus.fileName];
    
    // Setting just isDownloading without a concrete progress will show an indeterminate activity indicator
    [self didChangeIsDownloadingNotification:YES];
    
    // First read metadata from the file and check if we already downloaded it
    NKRequestOptions *options = [[NKRequestOptions alloc] initWithEndpoint:nil customHeader:nil customUserAgent:nil contentType:nil e2eToken:nil timeout:60 queue:dispatch_get_main_queue()];
    [[NextcloudKit shared] readFileOrFolderWithServerUrlFileName:serverUrlFileName depth:@"0" showHiddenFiles:NO includeHiddenFiles:@[] requestBody:nil options:options completion:^(NSString *account, NSArray<NKFile *> *files, NSData *responseDates, NKError *error) {
        if (error.errorCode == 0 && files.count == 1) {
            // File exists on server -> check our cache
            NKFile *file = files.firstObject;
        
            if ([self isFileInCache:self->_fileStatus.fileLocalPath withModificationDate:file.date withSize:file.size]) {
                NSLog(@"Found file in cache: %@", self->_fileStatus.fileLocalPath);
                
                [self.delegate fileControllerDidLoadFile:self withFileStatus:self->_fileStatus];
                [self didChangeIsDownloadingNotification:NO];
                
                return;
            }
            [[NextcloudKit shared] downloadWithServerUrlFileName:serverUrlFileName fileNameLocalPath:self->_fileStatus.fileLocalPath customUserAgent:nil addCustomHeaders:nil queue:dispatch_get_main_queue() taskHandler:^(NSURLSessionTask *task) {
                NSLog(@"Download task");
            } progressHandler:^(NSProgress *progress) {
                [self didChangeDownloadProgressNotification:progress];
            } completionHandler:^(NSString *account, NSString *etag, NSDate *date, int64_t length, NSDictionary *allHeaderFields, NKError *error) {
                if (error.errorCode == 0) {
                    // Set modification date to invalidate our cache
                    [self setModificationDateOnFile:self->_fileStatus.fileLocalPath withModificationDate:file.date];

                    // Set creation date to delete older files from cache
                    [self setCreationDateOnFile:self->_fileStatus.fileLocalPath withCreationDate:[NSDate date]];

                    [self.delegate fileControllerDidLoadFile:self withFileStatus:self->_fileStatus];
                } else {
                    NSLog(@"Error downloading file: %ld - %@", error.errorCode, error.errorDescription);
                    [self.delegate fileControllerDidFailLoadingFile:self withFileId:self->_fileStatus.fileId withErrorDescription:error.errorDescription];
                }

                [self didChangeIsDownloadingNotification:NO];
            }];
        } else {
            [self didChangeIsDownloadingNotification:NO];
            
            NSLog(@"Error downloading file: %ld - %@", error.errorCode, error.errorDescription);
            [self.delegate fileControllerDidFailLoadingFile:self withFileId:self->_fileStatus.fileId withErrorDescription:error.errorDescription];
        }
    }];
}

- (void)didChangeIsDownloadingNotification:(BOOL)isDownloading
{
    _fileStatus.isDownloading = isDownloading;
    
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_fileStatus forKey:@"fileStatus"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NCChatFileControllerDidChangeIsDownloadingNotification
                                                        object:self
                                                      userInfo:userInfo];
}

- (void)didChangeDownloadProgressNotification:(NSProgress *)progress
{
    _fileStatus.downloadProgress = progress.fractionCompleted;
    _fileStatus.canReportProgress = (progress.totalUnitCount != -1);

    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    [userInfo setObject:_fileStatus forKey:@"fileStatus"];
    [[NSNotificationCenter defaultCenter] postNotificationName:NCChatFileControllerDidChangeDownloadProgressNotification
                                                        object:self
                                                      userInfo:userInfo];
}

@end
