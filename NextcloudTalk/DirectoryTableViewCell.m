/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
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

#import "DirectoryTableViewCell.h"

#import "MaterialActivityIndicator.h"

#import "NCChatFileController.h"
#import "UIImageView+AFNetworking.h"

NSString *const kDirectoryCellIdentifier = @"DirectoryCellIdentifier";
NSString *const kDirectoryTableCellNibName = @"DirectoryTableViewCell";

CGFloat const kDirectoryTableCellHeight = 60.0f;

@interface DirectoryTableViewCell ()
{
    MDCActivityIndicator *_activityIndicator;
}

@end

@implementation DirectoryTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChangeIsDownloading:) name:NCChatFileControllerDidChangeIsDownloadingNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChangeDownloadProgress:) name:NCChatFileControllerDidChangeDownloadProgressNotification object:nil];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    
    // Fix problem of rendering downloaded image in a reused cell
    [self.fileImageView cancelImageDownloadTask];
    
    self.fileImageView.image = nil;
    self.fileNameLabel.text = @"";
    self.fileInfoLabel.text = @"";
}

- (void)didChangeIsDownloading:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NCChatFileStatus *receivedStatus = [notification.userInfo objectForKey:@"fileStatus"];
        
        if (![receivedStatus.fileId isEqualToString:self->_fileParameter.parameterId] || ![receivedStatus.filePath isEqualToString:self->_fileParameter.path]) {
            // Received a notification for a different cell
            return;
        }
        
        BOOL isDownloading = [[notification.userInfo objectForKey:@"isDownloading"] boolValue];
        
        if (isDownloading && !self->_activityIndicator) {
            // Immediately show an indeterminate indicator as long as we don't have a progress value
            [self addActivityIndicator:0];
        } else if (!isDownloading && self->_activityIndicator) {
            self.accessoryView = nil;
        }
    });
}
- (void)didChangeDownloadProgress:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NCChatFileStatus *receivedStatus = [notification.userInfo objectForKey:@"fileStatus"];
        
        if (![receivedStatus.fileId isEqualToString:self->_fileParameter.parameterId] || ![receivedStatus.filePath isEqualToString:self->_fileParameter.path]) {
            // Received a notification for a different cell
            return;
        }
        
        double progress = [[notification.userInfo objectForKey:@"progress"] doubleValue];

        if (self->_activityIndicator) {
            // Switch to determinate-mode and show progress
            self->_activityIndicator.indicatorMode = MDCActivityIndicatorModeDeterminate;
            [self->_activityIndicator setProgress:progress animated:YES];
        } else {
            // Make sure we have an activity indicator added to this cell
            [self addActivityIndicator:progress];
        }
    });
}

- (void)addActivityIndicator:(CGFloat)progress
{
    _activityIndicator = [[MDCActivityIndicator alloc] initWithFrame:CGRectMake(0, 0, 20, 20)];
    _activityIndicator.radius = 7.0f;
    _activityIndicator.cycleColors = @[UIColor.lightGrayColor];
    
    if (progress > 0) {
        _activityIndicator.indicatorMode = MDCActivityIndicatorModeDeterminate;
        [_activityIndicator setProgress:progress animated:NO];
    }
    
    [_activityIndicator startAnimating];
    self.accessoryView = _activityIndicator;
}

@end
