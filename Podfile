source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '10.0'

target "NextcloudTalk" do
pod 'AFNetworking', "3.1.0"
pod 'DateTools'
pod 'GoogleWebRTC', "1.1.31999"
pod 'JDStatusBarNotification'
pod 'SocketRocket'
pod 'DBImageColorPicker'
pod 'UICKeyChainStore'
pod 'Realm', '10.7.4'
pod "AFViewShaker", "~> 0.0.5"
pod 'BKPasscodeView', '~> 0.1.2'
pod 'MaterialComponents/ActivityIndicator'
pod 'Toast', '~> 4.0.0'
pod "PulsingHalo"
pod 'MBProgressHUD', '~> 1.2.0'
pod 'TOCropViewController', '~> 2.6.0'
pod 'libPhoneNumber-iOS'
end

target "NotificationServiceExtension" do
pod 'AFNetworking', "3.1.0"
pod 'UICKeyChainStore'
pod 'Realm', '10.7.4'
end

target "ShareExtension" do
pod 'AFNetworking', "3.1.0"
pod 'UICKeyChainStore'
pod 'Realm', '10.7.4'
pod 'MBProgressHUD', '~> 1.2.0'
pod 'TOCropViewController', '~> 2.6.0'
end

pre_install do |installer|
    puts 'pre_install begin....'
    dir_af = File.join(installer.sandbox.pod_dir('AFNetworking'), 'UIKit+AFNetworking')
    Dir.foreach(dir_af) {|x|
      real_path = File.join(dir_af, x)
      if (!File.directory?(real_path) && File.exists?(real_path))
        if((x.start_with?('UIWebView') || x == 'UIKit+AFNetworking.h'))
          File.delete(real_path)
          puts 'delete:'+ x
        end
      end
    }
    puts 'end pre_install.'
end

