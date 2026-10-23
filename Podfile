source 'https://cdn.cocoapods.org/'
platform :ios, '16.0'

def main_dependencies
  pod 'MaterialComponents/ActivityIndicator'
  pod 'MobileVLCKit', '~> 3.5.0'
end

target "NextcloudTalk" do
  main_dependencies

  target 'NextcloudTalkTests' do
    inherit! :search_paths
  end
end

# The extensions have no pods, they stay listed so CocoaPods keeps managing their configurations
target "NotificationServiceExtension" do
end

target "ShareExtension" do
end

target "BroadcastUploadExtension" do
end

target "TalkIntents" do
end

pre_install do |installer|
    puts 'pre_install begin....'

    puts 'Update submodules...'
    system('git submodule update --init')

    puts 'end pre_install.'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    if target.respond_to?(:product_type) and target.product_type == "com.apple.product-type.bundle"
      target.build_configurations.each do |config|
          config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      end
    end

    target.build_configurations.each do |config|
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
    end        
  end
end

