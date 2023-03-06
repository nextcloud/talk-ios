source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '14.0'

target "NextcloudTalk" do
pod 'AFNetworking', "3.2.0"
pod 'DateTools'
pod 'JDStatusBarNotification'
pod 'DBImageColorPicker'
pod 'UICKeyChainStore'
pod 'Realm', '10.30.0'
pod 'MaterialComponents/ActivityIndicator'
pod 'Toast', '~> 4.0.0'
pod 'MBProgressHUD', '~> 1.2.0'
pod 'TOCropViewController', '~> 2.6.0'
pod 'libPhoneNumber-iOS'
pod 'MZTimerLabel'
pod 'MobileVLCKit', '~>3.3.0'
end

target "NotificationServiceExtension" do
pod 'AFNetworking', "3.2.0"
pod 'UICKeyChainStore'
pod 'Realm', '10.30.0'
end

target "ShareExtension" do
pod 'AFNetworking', "3.2.0"
pod 'UICKeyChainStore'
pod 'Realm', '10.30.0'
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

post_install do |installer|
  installer.pods_project.targets.each do |target|
    if target.respond_to?(:product_type) and target.product_type == "com.apple.product-type.bundle"
      target.build_configurations.each do |config|
          config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      end
    end
  end
end

