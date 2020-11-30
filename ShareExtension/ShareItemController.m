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


- (void)addItemWithURL:(NSURL *)fileURL
{
    [self addItemWithURLAndName:fileURL withName:fileURL.lastPathComponent];
}

- (void)addItemWithURLAndName:(NSURL *)fileURL withName:(NSString *)fileName
{
    NSURL *fileLocalURL = [self.tempDirectoryURL URLByAppendingPathComponent:fileName];
    
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
    
    ShareItem* item = [ShareItem initWithURL:fileLocalURL withName:fileName withPlaceholderImage:[self getPlaceholderImageForFileURL:fileLocalURL]];
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
    NSURL *fileLocalURL = [self.tempDirectoryURL URLByAppendingPathComponent:imageName];
    
    //TODO: Should the quality be user-selectable?
    NSData *jpegData = UIImageJPEGRepresentation(image, 0.7);
    
    [jpegData writeToFile:fileLocalURL.path atomically:YES];
        
    NSLog(@"Adding shareItem with image: %@ %@", imageName, fileLocalURL);
    
    ShareItem* item = [ShareItem initWithURL:fileLocalURL withName:imageName withPlaceholderImage:[self getPlaceholderImageForFileURL:fileLocalURL]];

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

- (void)removeItem:(ShareItem *)item
{
    if ([NSFileManager.defaultManager fileExistsAtPath:item.filePath]) {
        [NSFileManager.defaultManager removeItemAtPath:item.filePath error:nil];
    }
    
    NSLog(@"Removing shareItem: %@ %@", item.fileName, item.fileURL);
    
    [self.shareItems removeObject:item];
    [self.delegate shareItemControllerItemsChanged:self];
}

- (UIImage *)getPlaceholderImageForFileURL:(NSURL *)fileURL
{
    CFStringRef fileExtension = (__bridge CFStringRef)[fileURL pathExtension];
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension, NULL);
    CFStringRef MIMEType = UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType);
    CFRelease(UTI);
     
    NSString *mimeType = (__bridge NSString *)MIMEType;
    NSString *imageName = [[NCUtils previewImageForFileMIMEType:mimeType] stringByAppendingString:@"-chat-preview"];
    return [UIImage imageNamed:imageName];
}

@end
