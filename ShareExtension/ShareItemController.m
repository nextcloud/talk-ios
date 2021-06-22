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

#import <MobileCoreServices/MobileCoreServices.h>

#import "ShareItemController.h"
#import "NCUtils.h"

//TODO: Should the quality be user-selectable?
CGFloat const kShareItemControllerImageQuality = 0.7f;

@interface ShareItemController ()

@property (nonatomic, strong) NSString *tempDirectoryPath;
@property (nonatomic, strong) NSURL *tempDirectoryURL;

@end

@implementation ShareItemController

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.shareItems = [[NSMutableArray alloc] init];
        [self initTempDirectory];
    }
    return self;
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

- (void)addItemWithURLAndName:(NSURL *)fileURL withName:(NSString *)fileName
{
    NSURL *fileLocalURL = [self getFileLocalURL:fileName];
    
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    __block NSError *error;
    
    // Make a local copy to prevent bug where file is removed after some time from inbox
    // See: https://stackoverflow.com/a/48007752/2512312
    [coordinator coordinateReadingItemAtURL:fileURL options:NSFileCoordinatorReadingForUploading error:&error byAccessor:^(NSURL *newURL) {
        if ([NSFileManager.defaultManager fileExistsAtPath:fileLocalURL.path]) {
            [NSFileManager.defaultManager removeItemAtPath:fileLocalURL.path error:nil];
        }
        
        [NSFileManager.defaultManager moveItemAtPath:newURL.path toPath:fileLocalURL.path error:nil];
    }];
    
    NSLog(@"Adding shareItem: %@ %@", fileName, fileLocalURL);
    
    // Try to determine if the item is an image file
    // This can happen when sharing an image from the native ios files app
    UIImage *image = [self getImageFromFileURL:fileLocalURL];
    BOOL fileIsImage = (image != nil);
    
    ShareItem* item = [ShareItem initWithURL:fileLocalURL withName:fileName withPlaceholderImage:[self getPlaceholderImageForFileURL:fileLocalURL] isImage:fileIsImage];
    [self.shareItems addObject:item];
    [self.delegate shareItemControllerItemsChanged:self];
}

- (void)addItemWithImage:(UIImage *)image
{
    NSString *imageName = [NSString stringWithFormat:@"IMG_%.f.jpg", [[NSDate date] timeIntervalSince1970] * 1000];
    [self addItemWithImageAndName:image withName:imageName];
}

- (void)addItemWithImageAndName:(UIImage *)image withName:(NSString *)imageName
{
    NSURL *fileLocalURL = [self getFileLocalURL:imageName];
    NSData *jpegData = UIImageJPEGRepresentation(image, kShareItemControllerImageQuality);
    
    [jpegData writeToFile:fileLocalURL.path atomically:YES];
        
    NSLog(@"Adding shareItem with image: %@ %@", imageName, fileLocalURL);
    
    ShareItem* item = [ShareItem initWithURL:fileLocalURL withName:imageName withPlaceholderImage:[self getPlaceholderImageForFileURL:fileLocalURL] isImage:YES];

    [self.shareItems addObject:item];
    [self.delegate shareItemControllerItemsChanged:self];
}

- (UIImage *)getImageFromItem:(ShareItem *)item
{
    if (!item || !item.fileURL) {
        return nil;
    }
        
    return [self getImageFromFileURL:item.fileURL];
}

- (UIImage *)getImageFromFileURL:(NSURL *)fileURL
{
    NSData *fileData = [NSData dataWithContentsOfURL:fileURL];
    UIImage *image = [UIImage imageWithData:fileData];
    
    return image;
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

    [self.shareItems addObject:item];
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
    [self cleanupItem:item];
    
    NSLog(@"Removing shareItem: %@ %@", item.fileName, item.fileURL);
    
    [self.shareItems removeObject:item];
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
    for (ShareItem *item in self.shareItems) {
        [self cleanupItem:item];
    }
    
    [self.shareItems removeAllObjects];
}

- (UIImage *)getPlaceholderImageForFileURL:(NSURL *)fileURL
{
    NSString *previewImage = [NCUtils previewImageForFileExtension:[fileURL pathExtension]];
    NSString *imageName = [previewImage stringByAppendingString:@"-chat-preview"];
    return [UIImage imageNamed:imageName];
}

@end
