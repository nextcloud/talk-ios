//
//  RoomsTableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "RoomsTableViewController.h"

#import "AFNetworking.h"
#import "CallViewController.h"
#import "ContactsTableViewController.h"
#import "AddParticipantsTableViewController.h"
#import "RoomTableViewCell.h"
#import "CCCertificate.h"
#import "NCAPIController.h"
#import "NCImageSessionManager.h"
#import "NCConnectionController.h"
#import "NCPushNotification.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NSDate+DateTools.h"
#import "UIImageView+Letters.h"
#import "AFImageDownloader.h"
#import "UIImageView+AFNetworking.h"

typedef void (^FetchRoomsCompletionBlock)(BOOL success);

@interface RoomsTableViewController () <CCCertificateDelegate>
{
    NSMutableArray *_rooms;
    UIRefreshControl *_refreshControl;
    BOOL _allowEmptyGroupRooms;
}

@end

@implementation RoomsTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _rooms = [[NSMutableArray alloc] init];
    
    [self createRefreshControl];
    
    AFImageDownloader *imageDownloader = [[AFImageDownloader alloc]
                                          initWithSessionManager:[NCImageSessionManager sharedInstance]
                                          downloadPrioritization:AFImageDownloadPrioritizationFIFO
                                          maximumActiveDownloads:4
                                          imageCache:[[AFAutoPurgingImageCache alloc] init]];
    
    [UIImageView setSharedImageDownloader:imageDownloader];
    
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"navigationLogo"]];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(serverCapabilitiesReceived:) name:NCServerCapabilitiesReceivedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinAudioCallAccepted:) name:NCPushNotificationJoinAudioCallAcceptedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(joinVideoCallAccepted:) name:NCPushNotificationJoinVideoCallAcceptedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appStateHasChanged:) name:NCAppStateHasChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionStateHasChanged:) name:NCConnectionStateHasChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userSelectedContactForVoiceCall:) name:NCSelectedContactForVoiceCallNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userSelectedContactForVideoCall:) name:NCSelectedContactForVideoCallNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self adaptInterfaceForAppState:[NCConnectionController sharedInstance].appState];
    [self adaptInterfaceForConnectionState:[NCConnectionController sharedInstance].connectionState];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Notifications

- (void)serverCapabilitiesReceived:(NSNotification *)notification
{
    NSDictionary *talkCapabilities = [NCSettingsController sharedInstance].ncTalkCapabilities;
    if (talkCapabilities) {
        NSArray *talkFeatures = [talkCapabilities objectForKey:@"features"];
        if ([talkFeatures containsObject:@"empty-group-room"]) {
            _allowEmptyGroupRooms = YES;
        }
    }
}

- (void)joinAudioCallAccepted:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [notification.userInfo objectForKey:@"pushNotification"];
    [self joinCallWithCallId:pushNotification.pnId audioOnly:YES];
}

- (void)joinVideoCallAccepted:(NSNotification *)notification
{
    NCPushNotification *pushNotification = [notification.userInfo objectForKey:@"pushNotification"];
    [self joinCallWithCallId:pushNotification.pnId audioOnly:NO];
}

- (void)appStateHasChanged:(NSNotification *)notification
{
    AppState appState = [[notification.userInfo objectForKey:@"appState"] intValue];
    [self adaptInterfaceForAppState:appState];
}

- (void)connectionStateHasChanged:(NSNotification *)notification
{
    ConnectionState connectionState = [[notification.userInfo objectForKey:@"connectionState"] intValue];
    [self adaptInterfaceForConnectionState:connectionState];
}

- (void)userSelectedContactForVoiceCall:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"token"];
    [self joinCallWithCallToken:roomToken audioOnly:YES];
}

- (void)userSelectedContactForVideoCall:(NSNotification *)notification
{
    NSString *roomToken = [notification.userInfo objectForKey:@"token"];
    [self joinCallWithCallToken:roomToken audioOnly:NO];
}

#pragma mark - Interface Builder Actions

- (IBAction)addButtonPressed:(id)sender
{
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:nil
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    if (_allowEmptyGroupRooms) {
        UIAlertAction *newGroupCallAction = [UIAlertAction actionWithTitle:@"New group call"
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^void (UIAlertAction *action) {
                                                                       [self startRoomCreationFlowForPublicRoom:NO];
                                                                   }];
        [newGroupCallAction setValue:[[UIImage imageNamed:@"group-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [optionsActionSheet addAction:newGroupCallAction];
    }
    
    UIAlertAction *newPublicCallAction = [UIAlertAction actionWithTitle:@"New public call"
                                                                  style:UIAlertActionStyleDefault
                                                                handler:^void (UIAlertAction *action) {
                                                                    [self startRoomCreationFlowForPublicRoom:YES];
                                                                }];
    [newPublicCallAction setValue:[[UIImage imageNamed:@"public-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [optionsActionSheet addAction:newPublicCallAction];
    
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

#pragma mark - User Interface

- (void)adaptInterfaceForAppState:(AppState)appState
{
    switch (appState) {
        case kAppStateReady:
        {
            [self fetchRoomsWithCompletionBlock:nil];
        }
            break;
            
        default:
            break;
    }
}

- (void)adaptInterfaceForConnectionState:(ConnectionState)connectionState
{
    switch (connectionState) {
        case kConnectionStateConnected:
        {
            [self setOnlineAppearance];
        }
            break;
            
        case kConnectionStateDisconnected:
        {
            [self setOfflineAppearance];
        }
            break;
            
        default:
            break;
    }
}

- (void)setOfflineAppearance
{
    self.addButton.enabled = NO;
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"navigationLogoOffline"]];
}

- (void)setOnlineAppearance
{
    self.addButton.enabled = YES;
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"navigationLogo"]];
}

#pragma mark - Rooms

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
    NSString *shareMessage = [NSString stringWithFormat:@"Join the conversation at %@/index.php/call/%@",
                              [[NCAPIController sharedInstance] currentServerUrl], room.token];
    if (room.name && ![room.name isEqualToString:@""]) {
        shareMessage = [NSString stringWithFormat:@"Join the conversation%@ at %@/index.php/call/%@",
                        [NSString stringWithFormat:@" \"%@\"", room.name], [[NCAPIController sharedInstance] currentServerUrl], room.token];
    }
    NSArray *items = @[shareMessage];
    UIActivityViewController *controller = [[UIActivityViewController alloc]initWithActivityItems:items applicationActivities:nil];
    
    NSString *appDisplayName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
    NSString *emailSubject = [NSString stringWithFormat:@"%@ invitation", appDisplayName];
    [controller setValue:emailSubject forKey:@"subject"];

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
    
    NSString *alertTitle = room.hasPassword ? @"Set new password:" : @"Set password:";
    UIAlertController *renameDialog =
    [UIAlertController alertControllerWithTitle:alertTitle
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    [renameDialog addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Password";
        textField.secureTextEntry = YES;
    }];
    
    NSString *actionTitle = room.hasPassword ? @"Change password" : @"OK";
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
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
    
    if (room.hasPassword) {
        UIAlertAction *removePasswordAction = [UIAlertAction actionWithTitle:@"Remove password" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [[NCAPIController sharedInstance] setPassword:@"" toRoom:room.token withCompletionBlock:^(NSError *error) {
                if (!error) {
                    [self fetchRoomsWithCompletionBlock:nil];
                } else {
                    NSLog(@"Error changing room password: %@", error.description);
                    //TODO: Error handling
                }
            }];
        }];
        [renameDialog addAction:removePasswordAction];
    }
    
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

- (void)createNewRoomWithName:(NSString *)roomName public:(BOOL)public
{
    [[NCAPIController sharedInstance] createRoomWith:nil
                                              ofType:public ? kNCRoomTypePublicCall : kNCRoomTypeGroupCall
                                             andName:roomName
                                 withCompletionBlock:^(NSString *token, NSError *error) {
        if (!error) {
            [self fetchRoomsWithCompletionBlock:^(BOOL success) {
                NCRoom *newRoom = [self getRoomForToken:token];
                NSInteger roomIndex = [_rooms indexOfObject:newRoom];
                if (roomIndex != NSNotFound) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSIndexPath *roomIndexPath = [NSIndexPath indexPathForRow:roomIndex inSection:0];
                        [self.tableView scrollToRowAtIndexPath:roomIndexPath atScrollPosition:UITableViewScrollPositionBottom animated:YES];
                    });
                }
                if (public) {
                    NSString *title = newRoom.name;
                    if (!title || [title isEqualToString:@""]) {
                        title = @"New public call";
                    }
                    [self showShareDialogForRoom:newRoom withTitle:title];
                }
            }];
        } else {
            NSLog(@"Error creating new group room: %@", error.description);
            //TODO: Error handling
        }
    }];
}

- (void)presentJoinCallOptionsForRoomAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:room.displayName
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *callAction = [UIAlertAction actionWithTitle:@"Call"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^void (UIAlertAction *action) {
                                                           [self startCallInRoom:room audioOnly:YES];
                                                       }];
    
    UIAlertAction *videocallAction = [UIAlertAction actionWithTitle:@"Video call"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^void (UIAlertAction *action) {
                                                           [self startCallInRoom:room audioOnly:NO];
                                                       }];
    
    [callAction setValue:[[UIImage imageNamed:@"call-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [videocallAction setValue:[[UIImage imageNamed:@"videocall-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    
    [optionsActionSheet addAction:callAction];
    [optionsActionSheet addAction:videocallAction];
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

#pragma mark - Public Calls

- (void)startRoomCreationFlowForPublicRoom:(BOOL)public
{
    NSString *alertTitle = public ? @"New public call" : @"New group call";
    UIAlertController *setNameDialog = [UIAlertController alertControllerWithTitle:alertTitle
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
        [self createNewRoomWithName:trimmedName public:public];
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

- (void)startCallInRoom:(NCRoom *)room audioOnly:(BOOL)audioOnly
{
    CallViewController *callVC = [[CallViewController alloc] initCallInRoom:room asUser:[[NCSettingsController sharedInstance] ncUserDisplayName] audioOnly:audioOnly];
    [[NCUserInterfaceController sharedInstance] presentCallViewController:callVC];
}

- (void)joinCallWithCallId:(NSInteger)callId audioOnly:(BOOL)audioOnly
{
    NCRoom *room = [self getRoomForId:callId];
    if (room) {
        [self startCallInRoom:room audioOnly:audioOnly];
    } else {
        //TODO: Show spinner?
        [[NCAPIController sharedInstance] getRoomWithId:callId withCompletionBlock:^(NCRoom *room, NSError *error) {
            if (!error) {
                [self startCallInRoom:room audioOnly:audioOnly];
            }
        }];
    }
}

- (void)joinCallWithCallToken:(NSString *)token audioOnly:(BOOL)audioOnly
{
    NCRoom *room = [self getRoomForToken:token];
    if (room) {
        [self startCallInRoom:room audioOnly:audioOnly];
    } else {
        //TODO: Show spinner?
        [[NCAPIController sharedInstance] getRoomWithToken:token withCompletionBlock:^(NCRoom *room, NSError *error) {
            if (!error) {
                [self startCallInRoom:room audioOnly:audioOnly];
            }
        }];
    }
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
        UIAlertAction *shareLinkAction = [UIAlertAction actionWithTitle:@"Share link"
                                                                  style:UIAlertActionStyleDefault
                                                                handler:^void (UIAlertAction *action) {
                                                                    [self shareLinkFromRoomAtIndexPath:indexPath];
                                                                }];
        [shareLinkAction setValue:[[UIImage imageNamed:@"public-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [optionsActionSheet addAction:shareLinkAction];
    // Moderator options
    } else {
        // Add participant
        UIAlertAction *addParticipantAction = [UIAlertAction actionWithTitle:@"Add participant"
                                                                       style:UIAlertActionStyleDefault
                                                                     handler:^void (UIAlertAction *action) {
                                                                         [self addParticipantInRoomAtIndexPath:indexPath];
                                                                     }];
        [addParticipantAction setValue:[[UIImage imageNamed:@"add-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [optionsActionSheet addAction:addParticipantAction];
        
        // Rename
        if (room.isNameEditable) {
            UIAlertAction *renameAction = [UIAlertAction actionWithTitle:@"Rename"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^void (UIAlertAction *action) {
                                                                     [self renameRoomAtIndexPath:indexPath];
                                                                 }];
            [renameAction setValue:[[UIImage imageNamed:@"rename-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            [optionsActionSheet addAction:renameAction];
        }
        
        // Public/Private room options
        if (room.isPublic) {
            
            // Set Password
            UIAlertAction *passwordAction = [UIAlertAction actionWithTitle:(room.hasPassword) ? @"Change password" : @"Set password"
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^void (UIAlertAction *action) {
                                                                       [self setPasswordToRoomAtIndexPath:indexPath];
                                                                   }];
            [passwordAction setValue:[[UIImage imageNamed:@"no-password-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            if (room.hasPassword) {
                [passwordAction setValue:[[UIImage imageNamed:@"password-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            }
            [optionsActionSheet addAction:passwordAction];
            
            // Share Link
            UIAlertAction *shareLinkAction = [UIAlertAction actionWithTitle:@"Share link"
                                                                      style:UIAlertActionStyleDefault
                                                                    handler:^void (UIAlertAction *action) {
                                                                        [self shareLinkFromRoomAtIndexPath:indexPath];
                                                                    }];
            [shareLinkAction setValue:[[UIImage imageNamed:@"public-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            [optionsActionSheet addAction:shareLinkAction];
            
            // Make call private
            UIAlertAction *makePrivateAction = [UIAlertAction actionWithTitle:@"Make call private"
                                                                        style:UIAlertActionStyleDefault
                                                                      handler:^void (UIAlertAction *action) {
                                                                          [self makePrivateRoomAtIndexPath:indexPath];
                                                                      }];
            [makePrivateAction setValue:[[UIImage imageNamed:@"group-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            [optionsActionSheet addAction:makePrivateAction];
        } else {
            // Make call public
            UIAlertAction *makePublicAction = [UIAlertAction actionWithTitle:@"Make call public"
                                                                       style:UIAlertActionStyleDefault
                                                                     handler:^void (UIAlertAction *action) {
                                                                         [self makePublicRoomAtIndexPath:indexPath];
                                                                     }];
            [makePublicAction setValue:[[UIImage imageNamed:@"public-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            [optionsActionSheet addAction:makePublicAction];
        }
        
        // Delete room
        if (room.isDeletable) {
            UIAlertAction *deleteCallAction = [UIAlertAction actionWithTitle:@"Delete call"
                                                                       style:UIAlertActionStyleDestructive
                                                                     handler:^void (UIAlertAction *action) {
                                                                         [self deleteRoomAtIndexPath:indexPath];
                                                                     }];
            [deleteCallAction setValue:[[UIImage imageNamed:@"delete-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
            [optionsActionSheet addAction:deleteCallAction];
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
            if (room.hasPassword) {
                [cell.roomPasswordImage setImage:[UIImage imageNamed:@"password"]];
            }
            break;
            
        default:
            break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([NCConnectionController sharedInstance].connectionState == kConnectionStateDisconnected) {
        [[NCUserInterfaceController sharedInstance] presentOfflineWarningAlert];
    } else {
        [self presentJoinCallOptionsForRoomAtIndexPath:indexPath];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}


@end
