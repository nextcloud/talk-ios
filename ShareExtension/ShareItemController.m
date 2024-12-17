/**
 * SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import <MobileCoreServices/MobileCoreServices.h>

#import "ShareItemController.h"
#import "NextcloudTalk-Swift.h"

//TODO: Should the quality be user-selectable?
CGFloat const kShareItemControllerImageQuality = 0.7f;

@interface ShareItemController ()

@property (nonatomic, strong) NSString *tempDirectoryPath;
@property (nonatomic, strong) NSURL *tempDirectoryURL;
@property (nonatomic, strong) NSMutableArray *internalShareItems;

@end

@implementation ShareItemController

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.internalShareItems = [[NSMutableArray alloc] init];
        [self initTempDirectory];
    }
    return self;
}

- (NSArray<ShareItem *> *)shareItems {
    return [self.internalShareItems copy];
}

- (void)initTempDirectory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    self.tempDirectoryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"/upload/"];
    
    if (![fileManager fileExistsAtPath:self.tempDirectoryPath]) {
        // Make sure our upload directory exists
        [fileManager createDirectoryAtPath:self.tempDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    } else {
        // Clean up any temporary files from a previous upload
        NSArray *previousFiles = [fileManager contentsOfDirectoryAtPath:self.tempDirectoryPath error:nil];
        
        for (NSString *previousFile in previousFiles) {
            [fileManager removeItemAtPath:[self.tempDirectoryPath stringByAppendingPathComponent:previousFile] error:nil];
        }
    }
    
    self.tempDirectoryURL = [NSURL fileURLWithPath:self.tempDirectoryPath isDirectory:YES];
}

- (NSURL *)getFileLocalURL:(NSString *)fileName
{
    NSURL *fileLocalURL = [self.tempDirectoryURL URLByAppendingPathComponent:fileName];
    
    if ([NSFileManager.defaultManager fileExistsAtPath:fileLocalURL.path]) {
        NSString *extension = [fileName pathExtension];
        NSString *nameWithoutExtension = [fileName stringByDeletingPathExtension];
        
        NSString *newFileName = [NSString stringWithFormat:@"%@%.f.%@", nameWithoutExtension, [[NSDate date] timeIntervalSince1970] * 1000, extension];
        fileLocalURL = [self.tempDirectoryURL URLByAppendingPathComponent:newFileName];
    }
    
    return fileLocalURL;
}

- (void)addItemWithURL:(NSURL *)fileURL
{
    [self addItemWithURLAndName:fileURL withName:fileURL.lastPathComponent];
}

- (BOOL)prepareFileForUploadingAtURL:(NSURL *)fileURL toLocalURL:(NSURL *)fileLocalURL withCoordinatorOption:(NSFileCoordinatorReadingOptions)options
{
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    __block NSError *error;

    // Make a local copy to prevent bug where file is removed after some time from inbox
    // See: https://stackoverflow.com/a/48007752/2512312
    [coordinator coordinateReadingItemAtURL:fileURL options:options error:&error byAccessor:^(NSURL *newURL) {
        if ([NSFileManager.defaultManager fileExistsAtPath:fileLocalURL.path]) {
            [NSFileManager.defaultManager removeItemAtPath:fileLocalURL.path error:nil];
        }

        [NSFileManager.defaultManager moveItemAtPath:newURL.path toPath:fileLocalURL.path error:nil];
    }];

    BOOL success = (error == nil);
    return success;
}

- (void)addItemWithURLAndName:(NSURL *)fileURL withName:(NSString *)fileName
{
    NSURL *fileLocalURL = [self getFileLocalURL:fileName];

    // First try to prepare the file with NSFileCoordinatorReadingForUploading
    BOOL preparedSuccessfully = [self prepareFileForUploadingAtURL:fileURL toLocalURL:fileLocalURL withCoordinatorOption:NSFileCoordinatorReadingForUploading];

    if (!preparedSuccessfully) {
        // We failed to prepare the file with NSFileCoordinatorReadingForUploading, use NSFileCoordinatorReadingWithoutChanges as a fallback
        preparedSuccessfully = [self prepareFileForUploadingAtURL:fileURL toLocalURL:fileLocalURL withCoordinatorOption:NSFileCoordinatorReadingWithoutChanges];

        if (!preparedSuccessfully) {
            NSLog(@"Failed to prepare file for sharing");
            return;
        }
    }

    NSLog(@"Adding shareItem: %@ %@", fileName, fileLocalURL);
    
    // Try to determine if the item is an image file
    // This can happen when sharing an image from the native ios files app
    NSString *extension = fileLocalURL.pathExtension;
    BOOL fileIsImage = (extension && [NCUtils isImageWithFileExtension:extension]);
    
    ShareItem* item = [ShareItem initWithURL:fileLocalURL withName:fileName withPlaceholderImage:[self getPlaceholderImageForFileURL:fileLocalURL] isImage:fileIsImage];
    [self.internalShareItems addObject:item];
    [self.delegate shareItemControllerItemsChanged:self];
}

- (void)addItemWithImage:(UIImage *)image
{
    NSString *imageName = [NSString stringWithFormat:@"IMG_%.f.jpg", [[NSDate date] timeIntervalSince1970] * 1000];
    [self addItemWithImageAndName:image withName:imageName];
}

- (void)addItemWithImageAndName:(UIImage *)image withName:(NSString *)imageName
{
    NSData *jpegData = UIImageJPEGRepresentation(image, kShareItemControllerImageQuality);
    [self addItemWithImageDataAndName:jpegData withName:imageName];
}

- (void)addItemWithImageDataAndName:(NSData *)data withName:(NSString *)imageName
{
    NSURL *fileLocalURL = [self getFileLocalURL:imageName];
    [data writeToFile:fileLocalURL.path atomically:YES];

    NSLog(@"Adding shareItem with image: %@ %@", imageName, fileLocalURL);

    ShareItem* item = [ShareItem initWithURL:fileLocalURL withName:imageName withPlaceholderImage:[self getPlaceholderImageForFileURL:fileLocalURL] isImage:YES];

    [self.internalShareItems addObject:item];
    [self.delegate shareItemControllerItemsChanged:self];
}

- (UIImage *)getImageFromItem:(ShareItem *)item
{
    if (!item || !item.fileURL) {
        return nil;
    }
        
    return [UIImage imageWithContentsOfFile:item.filePath];
}

- (void)addItemWithContactData:(NSData *)data
{
    NSString *vCardFileName = [NSString stringWithFormat:@"Contact_%.f.vcf", [[NSDate date] timeIntervalSince1970] * 1000];
    [self addItemWithContactDataAndName:data withName:vCardFileName];
}

- (void)addItemWithContactDataAndName:(NSData *)data withName:(NSString *)vCardFileName
{
    NSURL *fileLocalURL = [self getFileLocalURL:vCardFileName];
    NSString* vcString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    [vcString writeToFile:fileLocalURL.path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
    NSLog(@"Adding shareItem with contact: %@ %@", vCardFileName, fileLocalURL);
    
    ShareItem* item = [ShareItem initWithURL:fileLocalURL withName:vCardFileName withPlaceholderImage:[self getPlaceholderImageForFileURL:fileLocalURL] isImage:YES];

    [self.internalShareItems addObject:item];
    [self.delegate shareItemControllerItemsChanged:self];
}

- (void)updateItem:(ShareItem *)item withURL:(NSURL *)fileURL
{
    // This is called when an item was edited in quicklook and we want to use the edited image
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    __block NSError *error;
    
    [coordinator coordinateReadingItemAtURL:fileURL options:NSFileCoordinatorReadingForUploading error:&error byAccessor:^(NSURL *newURL) {
        if ([NSFileManager.defaultManager fileExistsAtPath:item.filePath]) {
            [NSFileManager.defaultManager removeItemAtPath:item.filePath error:nil];
        }
        
        [NSFileManager.defaultManager moveItemAtPath:newURL.path toPath:item.filePath error:nil];
    }];
    
    NSLog(@"Updating shareItem: %@ %@", item.fileName, item.fileURL);
    
    [self.delegate shareItemControllerItemsChanged:self];
}

- (void)updateItem:(ShareItem *)item withImage:(UIImage *)image
{
    NSData *jpegData = UIImageJPEGRepresentation(image, kShareItemControllerImageQuality);
    [jpegData writeToFile:item.filePath atomically:YES];
    
    NSLog(@"Updating shareItem with Image: %@ %@", item.fileName, item.fileURL);
    
    [self.delegate shareItemControllerItemsChanged:self];
}

- (void)removeItem:(ShareItem *)item
{
    [self removeItems:@[item]];
}

- (void)removeItems:(NSArray<ShareItem *> *)items
{
    for (ShareItem *item in items) {
        [self cleanupItem:item];

        NSLog(@"Removing shareItem: %@ %@", item.fileName, item.fileURL);
        [self.internalShareItems removeObject:item];
    }

    [self.delegate shareItemControllerItemsChanged:self];
}

- (void)cleanupItem:(ShareItem *)item
{
    if ([NSFileManager.defaultManager fileExistsAtPath:item.filePath]) {
        [NSFileManager.defaultManager removeItemAtPath:item.filePath error:nil];
    }
}

- (void)removeAllItems
{
    for (ShareItem *item in self.internalShareItems) {
        [self cleanupItem:item];
    }
    
    [self.internalShareItems removeAllObjects];
}

- (UIImage *)getPlaceholderImageForFileURL:(NSURL *)fileURL
{
    NSString *previewImage = [NCUtils previewImageForFileExtension:[fileURL pathExtension]];
    return [UIImage imageNamed:previewImage];
}

@end
