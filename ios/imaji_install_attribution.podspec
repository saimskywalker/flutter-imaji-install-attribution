#
# CocoaPods spec, kept for apps that have not moved to Swift Package Manager.
# The SwiftPM manifest (imaji_install_attribution/Package.swift) is primary.
#
Pod::Spec.new do |s|
  s.name             = 'imaji_install_attribution'
  s.version          = '0.1.0'
  s.summary          = 'Install attribution for Flutter: Apple AdServices token on iOS.'
  s.description      = <<-DESC
Flutter plugin that reads the Google Play Install Referrer on Android and the
Apple AdServices attribution token on iOS behind one typed Dart API.
                       DESC
  s.homepage         = 'https://github.com/saimskywalker/flutter-imaji-install-attribution'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'saimskywalker' => '15120878+saimskywalker@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'imaji_install_attribution/Sources/imaji_install_attribution/**/*.swift'
  s.resource_bundles = {
    'imaji_install_attribution_privacy' => ['imaji_install_attribution/Sources/imaji_install_attribution/PrivacyInfo.xcprivacy']
  }
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.frameworks = 'AdServices'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
