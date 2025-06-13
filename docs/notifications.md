
# Debugging push notifications

This list is intended to help users that have problems to receive talk notifications on their iOS device. It may 
not be complete. Please contribute to this list as you gain new knowledge. Just create an issue with the 
"notification" label or create a pull request for this document. 

# 📱 Users
Please make sure you're using the latest version available on the AppStore. Push notifications are not available if you're compiling and installing the app yourself through XCode.

[![Available on the AppStore](https://github.com/nextcloud/talk-ios/blob/main/docs/App%20Store/Download_on_the_App_Store_Badge.svg)](https://itunes.apple.com/app/id1296825574)

If you're using Talk 12 on the server, please make sure you're running atleast version 12.2.1 (see [here for details](https://github.com/nextcloud/spreed/pull/6329)).

Please note that under rare circumstances apple will stop sending (call-)notifications to your device. Those situations will usually resolve automatically after 24h. If your problem still occurs after checking all the hints below and you checked again after 24h, create an issue at https://github.com/nextcloud/talk-ios/issues

## 🍎 Check iOS settings

- Check that your phone is not in `do not disturb` or any `focus` (iOS >= 15) mode
- Check that your phone has internet access
- Check that notifications for `Nextcloud Talk` are allowed (Settings -> Nextcloud Talk -> Notifications)
  - `Allow notifications` should be turned on
  - All other settings depend on what you want to achieve. You can enable/disable notifications on the lockscreen or enable/disable the apps badge for example
 

## 🗨️ Check talk app settings

- In the conversation settings (tap the conversation name while in a conversation), check that notifications are set to 
  "Always notify" or "Notify when mentioned".
	- This is a per conversation setting. Set it for every conversation differently depending on your 
      needs.
    - If you're using Talk 13 or later, please note that notifications for chat messages and calls can be enabled/disabled independently for each conversation.
- Also be aware that notifications are not generated when you have an active session for a conversation! This also applies for tabs that are open in the background, etc. You might want to check if there's still a browser open somewhere preventing notifications to be send to your device(s).

## 🔒 Check app sessions

- Using the web interface go to your Nextcloud "Settings" -> "Security"
- Under "Devices & sessions" check if there are duplicate entries for the same device (e.g. iPhone (Nextcloud Talk))
- Remove old duplicate entries and just leave the entry with the most recent "Last activity"

## 🖥 Check server settings

Run the `notification:test-push` command for the user who is logged in at the device that should receive the notification:

```bash
sudo -u www-data php /var/www/yourinstance/occ notification:test-push --talk youruser
```

It should print something like the following:
```
Trying to push to 2 devices
  
Language is set to en
Private user key size: 1704
Public user key size: 451
Identified 1 Talk devices and 1 others.

Device token:156850
Device public key size: 451
Data to encrypt is: {"nid":525210,"app":"admin_notification_talk","subject":"Testing push notifications","type":"admin_notifications","id":"614aeee4"}
Signed encrypted push subject
Push notification sent successfully
```
This means the notifications are set up correctly on the server side and a test-notification is send to your device(s). Please note that depending on the app version two things can happen:

1. After about 30s a notification with the following text will be displayed: `You recieved a new notification that couldn't be decrypted`. This is totally fine and indicates, that push-notifications are working correctly. The version you're using doesn't support test-notifications, which results in the aforementioned timeout and message.
2. You'll receive a notification with "Testing push notifications" almost immediately.

If it prints something like
```
sudo -u www-data php /var/www/yourinstance/occ notification:test-push --talk youruser
No devices found for user
```
or you won't receive a notification after waiting a few minutes, try to remove the account from the Nextcloud iOS Talk app and log in again. Afterwards try to run the command
 again.
 
If it prints
```
There are no commands defined in the "notification" namespace. 
```
then the https://github.com/nextcloud/notifications app is not installed on your nextcloud instance.
The notification app is shipped and enabled by default, but could be missing in development environments or being disabled manually.
Install and enable the app by following the instructions at https://github.com/nextcloud/notifications#developers and
 try again to execute the command.
 
 ## ☁ Check if the push-proxy can be reached
 Your nextcloud server needs to be able to reach the push-proxy at `https://push-notifications.nextcloud.com`.
 ```
 curl https://push-notifications.nextcloud.com
 404 page not found
```
The return 404 error is fine in this case and indicates that a connection is possible. If you receive a different message, like `curl: (7) Failed to connect to push-notifications.nextcloud.com port 443: No route to host`, you might need to adjust your network- / firewall-settings.

# 🦺 Developers/testers
- Be aware that any self-compiled / self-installed app won't receive push-notifications.

- If you have access to the iOS console (via the MacOS Console app for example), you can filter for messages from `NotificationServiceExtension` to see if there're any messages indicating an error.
