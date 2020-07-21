source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '10.0'

target "VideoCalls" do
pod 'AFNetworking', "3.1.0"
pod 'DateTools'
pod 'GoogleWebRTC', "1.1.20266"
pod 'JDStatusBarNotification'
pod 'SocketRocket'
pod 'DBImageColorPicker'
pod 'UICKeyChainStore'
pod 'Realm'
pod "AFViewShaker", "~> 0.0.5"
pod 'BKPasscodeView', '~> 0.1.2'
pod 'MaterialComponents/ActivityIndicator'
pod 'Toast', '~> 4.0.0'
pod "PulsingHalo"
end

target "NotificationServiceExtension" do
pod 'AFNetworking', "3.1.0"
pod 'DateTools'
pod 'GoogleWebRTC', "1.1.20266"
pod 'JDStatusBarNotification'
pod 'SocketRocket'
pod 'DBImageColorPicker'
pod 'UICKeyChainStore'
pod 'Realm'
pod "AFViewShaker", "~> 0.0.5"
pod 'BKPasscodeView', '~> 0.1.2'
pod 'MaterialComponents/ActivityIndicator'
pod 'Toast', '~> 4.0.0'
pod "PulsingHalo"
end

target "ShareExtension" do
pod 'AFNetworking', "3.1.0"
pod 'DateTools'
pod 'GoogleWebRTC', "1.1.20266"
pod 'JDStatusBarNotification'
pod 'SocketRocket'
pod 'DBImageColorPicker'
pod 'UICKeyChainStore'
pod 'Realm'
pod "AFViewShaker", "~> 0.0.5"
pod 'BKPasscodeView', '~> 0.1.2'
pod 'MaterialComponents/ActivityIndicator'
pod 'Toast', '~> 4.0.0'
pod "PulsingHalo"
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'NO'
    end
  end
end

