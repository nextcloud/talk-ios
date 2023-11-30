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

#import "RoomDescriptionTableViewCell.h"

NSString *const kRoomDescriptionCellIdentifier     = @"RoomDescriptionCellIdentifier";
NSString *const kRoomDescriptionTableCellNibName   = @"RoomDescriptionTableViewCell";

@interface RoomDescriptionTableViewCell () <UITextViewDelegate>

@property (nonatomic, strong) NSString *originalText;

@end

@implementation RoomDescriptionTableViewCell

- (void)awakeFromNib
{
    [super awakeFromNib];

    self.textView.dataDetectorTypes = UIDataDetectorTypeAll;
    self.textView.textContainer.lineFragmentPadding = 0;
    self.textView.textContainerInset = UIEdgeInsetsZero;
    self.textView.scrollEnabled = NO;
    self.textView.delegate = self;
    self.editable = NO;
    self.characterLimit = -1;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)setEditable:(BOOL)editable
{
    _editable = editable;

    self.textView.editable = editable;

    if (editable) {
        [self createKeyboardToolbar];
    } else {
        self.textView.inputAccessoryView = nil;
    }
}

- (void)createKeyboardToolbar
{
    UIToolbar* keyboardToolbar = [[UIToolbar alloc] init];
    UIBarButtonItem *cancelBarButton = [[UIBarButtonItem alloc]
                                        initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                        target:self action:@selector(cancelButtonPressed)];
    UIBarButtonItem *flexBarButton = [[UIBarButtonItem alloc]
                                      initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                      target:nil action:nil];
    UIBarButtonItem *doneBarButton = [[UIBarButtonItem alloc]
                                      initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                      target:self action:@selector(doneButtonPressed)];

    keyboardToolbar.items = @[cancelBarButton, flexBarButton, doneBarButton];
    [keyboardToolbar sizeToFit];
    self.textView.inputAccessoryView = keyboardToolbar;
}

- (void)cancelButtonPressed
{
    [self.textView resignFirstResponder];

    self.textView.text = self.originalText;
    [self.delegate roomDescriptionCellTextViewDidChange:self];
}

- (void)doneButtonPressed
{
    [self.textView resignFirstResponder];

    if (![self.originalText isEqualToString:self.textView.text]) {
        [self.delegate roomDescriptionCellDidConfirmChanges:self];
    }
}

#pragma mark - UITextView delegate

- (void)textViewDidChange:(UITextView *)textView
{
    [self.delegate roomDescriptionCellTextViewDidChange:self];
}

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    self.originalText = self.textView.text;
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    // Prevent crashing undo bug
    // https://stackoverflow.com/questions/433337/set-the-maximum-character-length-of-a-uitextfield
    if (range.length + range.location > textView.text.length) {
        return NO;
    }
    // Check character limit
    NSUInteger newLength = [textView.text length] + [text length] - range.length;
    BOOL limitExceeded = _characterLimit > 0 && newLength > _characterLimit;
    if (limitExceeded) {
        [self.delegate roomDescriptionCellDidExceedLimit:self];
    }
    return !limitExceeded;
}


@end
