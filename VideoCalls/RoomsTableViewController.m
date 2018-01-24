//
//  RoomsTableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "RoomsTableViewController.h"

#import "AFNetworking.h"
#import "AuthenticationViewController.h"
#import "CallViewController.h"
#import "AddParticipantsTableViewController.h"
#import "CCCertificate.h"
#import "RoomTableViewCell.h"
#import "LoginViewController.h"
#import "NCAPIController.h"
#import "NCImageSessionManager.h"
#import "NCConnectionController.h"
#import "NCPushNotification.h"
#import "NCSettingsController.h"
#import "NSDate+DateTools.h"
#import "UIImageView+Letters.h"
#import "AFImageDownloader.h"
#import "UIImageView+AFNetworking.h"

typedef void (^FetchRoomsCompletionBlock)(BOOL success);

@interface RoomsTableViewController () <CallViewControllerDelegate, CCCertificateDelegate>
{
    NSMutableArray *_rooms;
    BOOL _networkDisconnectedRetry;
    UIRefreshControl *_refreshControl;
    NSTimer *_pingTimer;
    NSString *_currentCallToken;
}

@end

@implementation RoomsTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _rooms = [[NSMutableArray alloc] init];
    _networkDisconnectedRetry = NO;
    
    [self createRefreshControl];
    
    AFImageDownloader *imageDownloader = [[AFImageDownloader alloc]
                                          initWithSessionManager:[NCImageSessionManager sharedInstance]
                                          downloadPrioritization:AFImageDownloadPrioritizationFIFO
                                          maximumActiveDownloads:4
                                          imageCache:[[AFAutoPurgingImageCache alloc] init]];
    
    [UIImageView setSharedImageDownloader:imageDownloader];
    
    UIImage *image = [UIImage imageNamed:@"navigationLogo"];
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:image];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loginHasBeenCompleted:) name:NCLoginCompletedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pushNotificationReceived:) name:NCPushNotificationReceivedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinCallAccepted:) name:NCPushNotificationJoinCallAcceptedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkReachabilityHasChanged:) name:NCNetworkReachabilityHasChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(roomHasBeenCreated:) name:NCRoomCreatedNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self checkConnectionState];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Notifications

- (void)loginHasBeenCompleted:(NSNotification *)notification
{
    if ([notification.userInfo objectForKey:kNCTokenKey]) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)pushNotificationReceived:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [NCPushNotification pushNotificationFromDecryptedString:[notification.userInfo objectForKey:@"message"]];
    NSLog(@"Push Notification received: %@", pushNotification);
    if (!_currentCallToken) {
        if (self.presentedViewController) {
            [self dismissViewControllerAnimated:YES completion:^{
                [self presentPushNotificationAlert:pushNotification];
            }];
        } else {
            [self presentPushNotificationAlert:pushNotification];
        }
    }
}

- (void)joinCallAccepted:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [NCPushNotification pushNotificationFromDecryptedString:[notification.userInfo objectForKey:@"message"]];
    [self joinCallWithCallId:pushNotification.pnId];
}

- (void)networkReachabilityHasChanged:(NSNotification *)notification
{
    AFNetworkReachabilityStatus status = [[notification.userInfo objectForKey:kNCNetworkReachabilityKey] intValue];
    NSLog(@"Network Status:%ld", (long)status);
}

- (void)roomHasBeenCreated:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"token"];
    NCRoom *room = [self getRoomForToken:roomToken];
    if (room) {
        [self startCallInRoom:room];
    } else {
        //TODO: Show spinner?
        [[NCAPIController sharedInstance] getRoomWithToken:roomToken withCompletionBlock:^(NCRoom *room, NSError *error) {
            if (!error) {
                [self startCallInRoom:room];
            }
        }];
    }
}

#pragma mark - Push Notification Actions

- (void)presentPushNotificationAlert:(NCPushNotification *)pushNotification
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:[pushNotification bodyForRemoteAlerts]
                                 message:@"Do you want to join this call?"
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *joinButton = [UIAlertAction
                                 actionWithTitle:@"Join call"
                                 style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction * _Nonnull action) {
                                     [self joinCallWithCallId:pushNotification.pnId];
                                 }];
    
    UIAlertAction* cancelButton = [UIAlertAction
                                   actionWithTitle:@"Cancel"
                                   style:UIAlertActionStyleCancel
                                   handler:nil];
    
    [alert addAction:joinButton];
    [alert addAction:cancelButton];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)joinCallWithCallId:(NSInteger)callId
{
    NCRoom *room = [self getRoomForId:callId];
    if (room) {
        [self startCallInRoom:room];
    } else {
        //TODO: Show spinner?
        [[NCAPIController sharedInstance] getRoomWithId:callId withCompletionBlock:^(NCRoom *room, NSError *error) {
            if (!error) {
                [self startCallInRoom:room];
            }
        }];
    }
}

#pragma mark - Interface Builder Actions

- (IBAction)addButtonPressed:(id)sender
{
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:nil
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"New public call"
                                                           style:UIAlertActionStyleDefault
                                                         handler:^void (UIAlertAction *action) {
                                                             [self startPublicCallCreationFlow];
                                                         }]];
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    UIPopoverPresentationController *popController = [optionsActionSheet popoverPresentationController];
    popController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    popController.barButtonItem = self.navigationItem.rightBarButtonItem;
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

#pragma mark - Refresh Control

- (void)createRefreshControl
{
    _refreshControl = [UIRefreshControl new];
    _refreshControl.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    _refreshControl.backgroundColor = [UIColor colorWithRed:235.0/255.0 green:235.0/255.0 blue:235.0/255.0 alpha:1.0];
    [_refreshControl addTarget:self action:@selector(refreshControlTarget) forControlEvents:UIControlEventValueChanged];
    [self setRefreshControl:_refreshControl];
}

- (void)deleteRefreshControl
{
    [_refreshControl endRefreshing];
    self.refreshControl = nil;
}

- (void)refreshControlTarget
{
    [self fetchRoomsWithCompletionBlock:nil];
    
    // Actuate `Peek` feedback (weak boom)
    AudioServicesPlaySystemSound(1519);
}

#pragma mark - Rooms

- (void)checkConnectionState
{
    ConnectionState connectionState = [[NCConnectionController sharedInstance] connectionState];
    
    switch (connectionState) {
        case kConnectionStateNotServerProvided:
        {
            LoginViewController *loginVC = [[LoginViewController alloc] init];
            [self presentViewController:loginVC animated:YES completion:nil];
        }
            break;
        case kConnectionStateAuthenticationNeeded:
        {
            AuthenticationViewController *authVC = [[AuthenticationViewController alloc] init];
            [self presentViewController:authVC animated:YES completion:nil];
        }
            break;
            
        case kConnectionStateNetworkDisconnected:
        {
            NSLog(@"No network connection!");
            if (!_networkDisconnectedRetry) {
                _networkDisconnectedRetry = YES;
                double delayInSeconds = 1.0;
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                    [self checkConnectionState];
                });
            }
        }
            break;
            
        default:
        {
            [self fetchRoomsWithCompletionBlock:nil];
            _networkDisconnectedRetry = NO;
        }
            break;
    }
}

- (void)fetchRoomsWithCompletionBlock:(FetchRoomsCompletionBlock)block
{
    [[NCAPIController sharedInstance] getRoomsWithCompletionBlock:^(NSMutableArray *rooms, NSError *error, NSInteger statusCode) {
        if (!error) {
            _rooms = rooms;
            [self.tableView reloadData];
            NSLog(@"Rooms updated");
            if (block) {
                block(YES);
            }
        } else {
            NSLog(@"Error while trying to get rooms: %@", error);
            if ([error code] == NSURLErrorServerCertificateUntrusted) {
                NSLog(@"Untrusted certificate");
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[CCCertificate sharedManager] presentViewControllerCertificateWithTitle:[error localizedDescription] viewController:self delegate:self];
                });
                
            }
            if (block) {
                block(NO);
            }
        }
        
        [_refreshControl endRefreshing];
    }];
}

- (void)trustedCerticateAccepted
{
    [self fetchRoomsWithCompletionBlock:nil];
}

- (void)startPingCall
{
    [self pingCall];
    _pingTimer = [NSTimer scheduledTimerWithTimeInterval:5.0  target:self selector:@selector(pingCall) userInfo:nil repeats:YES];
}

- (void)pingCall
{
    if (_currentCallToken) {
        [[NCAPIController sharedInstance] pingCall:_currentCallToken withCompletionBlock:^(NSError *error) {
            //TODO: Error handling
        }];
    } else {
        NSLog(@"No call token to ping");
    }
}

#pragma mark - Room actions

- (void)addParticipantInRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    AddParticipantsTableViewController *addParticipantsVC = [[AddParticipantsTableViewController alloc] initForRoom:room];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:addParticipantsVC];
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)renameRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    
    UIAlertController *renameDialog =
    [UIAlertController alertControllerWithTitle:@"Enter new name:"
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    [renameDialog addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Name";
        textField.text = room.displayName;
        textField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
        textField.autocorrectionType = UITextAutocorrectionTypeDefault;
    }];
    
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *newRoomName = [[renameDialog textFields][0] text];
        NSString *trimmedName = [newRoomName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [[NCAPIController sharedInstance] renameRoom:room.token withName:trimmedName andCompletionBlock:^(NSError *error) {
            if (!error) {
                [self fetchRoomsWithCompletionBlock:nil];
            } else {
                NSLog(@"Error renaming the room: %@", error.description);
                //TODO: Error handling
            }
        }];
    }];
    [renameDialog addAction:confirmAction];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [renameDialog addAction:cancelAction];
    
    [self presentViewController:renameDialog animated:YES completion:nil];
}

- (void)shareLinkFromRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    NSString *shareMessage = [NSString stringWithFormat:@"You can join to this call: %@/index.php/call/%@", [[NCAPIController sharedInstance] currentServerUrl], room.token];
    NSArray *items = @[shareMessage];
    
    UIActivityViewController *controller = [[UIActivityViewController alloc]initWithActivityItems:items applicationActivities:nil];
    
    // Presentation on iPads
    controller.popoverPresentationController.sourceView = self.tableView;
    controller.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    [self presentViewController:controller animated:YES completion:nil];
    
    controller.completionWithItemsHandler = ^(NSString *activityType,
                                              BOOL completed,
                                              NSArray *returnedItems,
                                              NSError *error) {
        if (error) {
            NSLog(@"An Error occured sharing room: %@, %@", error.localizedDescription, error.localizedFailureReason);
        }
    };
}

- (void)makePublicRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    [[NCAPIController sharedInstance] makeRoomPublic:room.token withCompletionBlock:^(NSError *error) {
        if (!error) {
            NSString *title = [NSString stringWithFormat:@"%@ is now public", room.name];
            // Room type condition should be removed when we don't set room names by default on OneToOne calls.
            if (room.type == kNCRoomTypeOneToOneCall || !room.name || [room.name isEqualToString:@""]) {
                title = @"This call is now public";
            }
            [self showShareDialogForRoom:room withTitle:title];
            [self fetchRoomsWithCompletionBlock:nil];
        } else {
            NSLog(@"Error making public the room: %@", error.description);
            //TODO: Error handling
        }
    }];
}

- (void)makePrivateRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    [[NCAPIController sharedInstance] makeRoomPrivate:room.token withCompletionBlock:^(NSError *error) {
        if (!error) {
            [self fetchRoomsWithCompletionBlock:nil];
        } else {
            NSLog(@"Error making private the room: %@", error.description);
            //TODO: Error handling
        }
    }];
}

- (void)setPasswordToRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    
    UIAlertController *renameDialog =
    [UIAlertController alertControllerWithTitle:@"Set password:"
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    [renameDialog addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Password";
        textField.secureTextEntry = YES;
    }];
    
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *password = [[renameDialog textFields][0] text];
        NSString *trimmedPassword = [password stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [[NCAPIController sharedInstance] setPassword:trimmedPassword toRoom:room.token withCompletionBlock:^(NSError *error) {
            if (!error) {
                [self fetchRoomsWithCompletionBlock:nil];
            } else {
                NSLog(@"Error setting room password: %@", error.description);
                //TODO: Error handling
            }
        }];
    }];
    [renameDialog addAction:confirmAction];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [renameDialog addAction:cancelAction];
    
    [self presentViewController:renameDialog animated:YES completion:nil];
}

- (void)leaveRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    [[NCAPIController sharedInstance] removeSelfFromRoom:room.token withCompletionBlock:^(NSError *error) {
        if (error) {
            //TODO: Error handling
        }
    }];
    
    [_rooms removeObjectAtIndex:indexPath.row];
    [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)deleteRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    [[NCAPIController sharedInstance] deleteRoom:room.token withCompletionBlock:^(NSError *error) {
        if (error) {
            //TODO: Error handling
        }
    }];
    
    [_rooms removeObjectAtIndex:indexPath.row];
    [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)createNewPublicRoomWithName:(NSString *)roomName
{
    [[NCAPIController sharedInstance] createRoomWith:nil ofType:kNCRoomTypePublicCall andName:roomName withCompletionBlock:^(NSString *token, NSError *error) {
        if (!error) {
            [self fetchRoomsWithCompletionBlock:^(BOOL success) {
                NCRoom *newPublicRoom = [self getRoomForToken:token];
                NSInteger roomIndex = [_rooms indexOfObject:newPublicRoom];
                if (roomIndex != NSNotFound) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSIndexPath *roomIndexPath = [NSIndexPath indexPathForRow:roomIndex inSection:0];
                        [self.tableView scrollToRowAtIndexPath:roomIndexPath atScrollPosition:UITableViewScrollPositionBottom animated:YES];
                    });
                    NSString *title = newPublicRoom.name;
                    if (!title || [title isEqualToString:@""]) {
                        title = @"New public call";
                    }
                    [self showShareDialogForRoom:newPublicRoom withTitle:title];
                }
            }];
        } else {
            NSLog(@"Error creating new public room: %@", error.description);
            //TODO: Error handling
        }
    }];
}

#pragma mark - Public Calls

- (void)startPublicCallCreationFlow
{
    UIAlertController *setNameDialog =
    [UIAlertController alertControllerWithTitle:@"New public call"
                                        message:@"Set a name for this call"
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    [setNameDialog addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Name";
        textField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
        textField.autocorrectionType = UITextAutocorrectionTypeDefault;
    }];
    
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *publicCallName = [[setNameDialog textFields][0] text];
        NSString *trimmedName = [publicCallName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [self createNewPublicRoomWithName:trimmedName];
    }];
    [setNameDialog addAction:confirmAction];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [setNameDialog addAction:cancelAction];
    
    [self presentViewController:setNameDialog animated:YES completion:nil];
}

- (void)showShareDialogForRoom:(NCRoom *)room withTitle:(NSString *)title
{
    NSInteger roomIndex = [_rooms indexOfObject:room];
    NSIndexPath *roomIndexPath = [NSIndexPath indexPathForRow:roomIndex inSection:0];
    
    UIAlertController *shareRoomDialog =
    [UIAlertController alertControllerWithTitle:title
                                        message:@"Do you want to share this call with others?"
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self shareLinkFromRoomAtIndexPath:roomIndexPath];
    }];
    [shareRoomDialog addAction:confirmAction];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Not now" style:UIAlertActionStyleCancel handler:nil];
    [shareRoomDialog addAction:cancelAction];
    
    [self presentViewController:shareRoomDialog animated:YES completion:nil];
}

#pragma mark - Calls

- (NCRoom *)getRoomForToken:(NSString *)token
{
    NCRoom *room = nil;
    for (NCRoom *localRoom in _rooms) {
        if (localRoom.token == token) {
            room = localRoom;
        }
    }
    return room;
}

- (NCRoom *)getRoomForId:(NSInteger)roomId
{
    NCRoom *room = nil;
    for (NCRoom *localRoom in _rooms) {
        if (localRoom.roomId == roomId) {
            room = localRoom;
        }
    }
    return room;
}

- (void)presentCall:(CallViewController *)callVC
{
    [self presentViewController:callVC animated:YES completion:^{
        // Disable sleep timer
        [UIApplication sharedApplication].idleTimerDisabled = YES;
    }];
}

- (void)presentCallViewController:(CallViewController *)callVC
{
    if (self.presentedViewController) {
        [self dismissViewControllerAnimated:YES completion:^{
            [self presentCall:callVC];
        }];
    } else {
        [self presentCall:callVC];
    }
}

- (void)startCallInRoom:(NCRoom *)room
{
    CallViewController *callVC = [[CallViewController alloc] initCallInRoom:room asUser:[[NCSettingsController sharedInstance] ncUserDisplayName]];
    callVC.delegate = self;
    [self presentCallViewController:callVC];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _rooms.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60.0f;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleDelete;
}

- (NSString *)tableView:(UITableView *)tableView titleForSwipeAccessoryButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    
    if (room.canModerate || room.isPublic) {
        NSString *moreButtonText = @"More";
        return moreButtonText;
    }
    
    return nil;
}

- (void)tableView:(UITableView *)tableView swipeAccessoryButtonPushedForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:room.displayName
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Share link of public calls even if you are not a moderator
    if (!room.canModerate && room.isPublic) {
        // Share Link
        [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Share link"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^void (UIAlertAction *action) {
                                                                 [self shareLinkFromRoomAtIndexPath:indexPath];
                                                             }]];
    // Moderator options
    } else {
        // Add participant
        [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Add participant"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^void (UIAlertAction *action) {
                                                                 [self addParticipantInRoomAtIndexPath:indexPath];
                                                             }]];
        
        // Rename
        if (room.isNameEditable) {
            [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Rename"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^void (UIAlertAction *action) {
                                                                     [self renameRoomAtIndexPath:indexPath];
                                                                 }]];
        }
        
        // Public/Private room options
        if (room.isPublic) {
            
            // Set Password
            NSString *passwordOptionTitle = @"Set password";
            if (room.hasPassword) {
                passwordOptionTitle = @"Change password";
            }
            [optionsActionSheet addAction:[UIAlertAction actionWithTitle:passwordOptionTitle
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^void (UIAlertAction *action) {
                                                                     [self setPasswordToRoomAtIndexPath:indexPath];
                                                                 }]];
            
            // Share Link
            [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Share link"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^void (UIAlertAction *action) {
                                                                     [self shareLinkFromRoomAtIndexPath:indexPath];
                                                                 }]];
            
            // Make call private
            [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Make call private"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^void (UIAlertAction *action) {
                                                                     [self makePrivateRoomAtIndexPath:indexPath];
                                                                 }]];
        } else {
            // Make call public
            [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Make call public"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^void (UIAlertAction *action) {
                                                                     [self makePublicRoomAtIndexPath:indexPath];
                                                                 }]];
        }
        
        // Delete room
        if (room.isDeletable) {
            [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Delete call"
                                                                   style:UIAlertActionStyleDestructive
                                                                 handler:^void (UIAlertAction *action) {
                                                                     [self deleteRoomAtIndexPath:indexPath];
                                                                 }]];
        }
        
    }
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *deleteButtonText = @"Leave";
    return deleteButtonText;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [self leaveRoomAtIndexPath:indexPath];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    RoomTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRoomCellIdentifier];
    if (!cell) {
        cell = [[RoomTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kRoomCellIdentifier];
    }
    
    // Set room name
    cell.labelTitle.text = room.displayName;
    
    // Set last ping
    NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:room.lastPing];
    cell.labelSubTitle.text = [date timeAgoSinceNow];
    
    if (room.lastPing == 0) {
        cell.labelSubTitle.text = @"Never joined";
    }
    
    // Set room image
    switch (room.type) {
        case kNCRoomTypeOneToOneCall:
        {
            // Create avatar for every OneToOne call
            [cell.roomImage setImageWithString:room.displayName color:nil circular:true];
            
            // Request user avatar to the server and set it if exist
            [cell.roomImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:room.name andSize:96]
                                  placeholderImage:nil success:nil failure:nil];
        }
            break;
            
        case kNCRoomTypeGroupCall:
            [cell.roomImage setImage:[UIImage imageNamed:@"group-white"]];
            cell.roomImage.backgroundColor = [UIColor colorWithRed:0.84 green:0.84 blue:0.84 alpha:1.0]; /*#d5d5d5*/
            cell.roomImage.contentMode = UIViewContentModeCenter;
            break;
            
        case kNCRoomTypePublicCall:
            [cell.roomImage setImage:[UIImage imageNamed:@"public-white"]];
            cell.roomImage.backgroundColor = [UIColor colorWithRed:0.84 green:0.84 blue:0.84 alpha:1.0]; /*#d5d5d5*/
            cell.roomImage.contentMode = UIViewContentModeCenter;
            break;
            
        default:
            break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    
    _currentCallToken = room.token;
    [self startCallInRoom:room];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - CallViewControllerDelegate

- (void)viewControllerDidFinish:(CallViewController *)viewController {
    if (![viewController isBeingDismissed]) {
        [self dismissViewControllerAnimated:YES completion:^{
            NSLog(@"Call view controller dismissed");
            _currentCallToken = nil;
            // Enable sleep timer
            [UIApplication sharedApplication].idleTimerDisabled = NO;
        }];
    }
}


@end
