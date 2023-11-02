source 'https://cdn.cocoapods.org/'
platform :ios, '15.0'

def common_dependencies
pod 'AFNetworking', '3.2.0'
pod 'UICKeyChainStore'
end

def common_dependencies_ext
common_dependencies
pod 'MBProgressHUD', '~> 1.2.0'
end

target "NextcloudTalk" do
common_dependencies_ext
pod 'DateTools'
pod 'JDStatusBarNotification', '~> 2.0.0'
pod 'MaterialComponents/ActivityIndicator'
pod 'Toast', '~> 4.0.0'
pod 'libPhoneNumber-iOS'
pod 'MZTimerLabel'
pod 'MobileVLCKit', '~> 3.5.0'
end

target "NotificationServiceExtension" do
common_dependencies
end

target "ShareExtension" do
common_dependencies_ext
end

pre_install do |installer|
    puts 'pre_install begin....'

    puts 'Update submodules...'
    system('git submodule update --init')

    dir_af = File.join(installer.sandbox.pod_dir('AFNetworking'), 'UIKit+AFNetworking')
    Dir.foreach(dir_af) {|x|
      real_path = File.join(dir_af, x)
      if (!File.directory?(real_path) && File.exist?(real_path))
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

