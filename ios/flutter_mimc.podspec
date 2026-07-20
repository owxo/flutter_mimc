Pod::Spec.new do |s|
  s.name             = 'flutter_mimc'
  s.version          = '2.0.0-dev.3'
  s.summary          = 'Flutter plugin for Xiaomi MIMC.'
  s.description      = 'Maintained Flutter bindings for the Xiaomi MIMC iOS SDK.'
  s.homepage         = 'https://github.com/owxo/flutter_mimc'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'flutter_mimc contributors' => 'mimc-help@xiaomi.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/FlutterMimcPlugin.{h,mm}'
  s.public_header_files = 'Classes/FlutterMimcPlugin.h'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.libraries = 'c++'
  s.frameworks = 'CoreTelephony', 'SystemConfiguration'
  s.vendored_frameworks = 'Frameworks/MIMCProtoBuffer.framework',
                          'Frameworks/MMCSDK.framework'
  s.resource_bundles = {
    'flutter_mimc_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }
  simulator_arch_settings = {
    # The arm64 slice in Xiaomi's legacy fat framework targets physical iOS,
    # not the arm64 simulator. Force x86_64 as well as excluding unsupported
    # slices because Flutter's Generated.xcconfig can override exclusions in
    # a consuming app after CocoaPods' xcconfig has been included.
    'ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64 i386'
  }
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'DEFINES_MODULE' => 'YES',
  }.merge(simulator_arch_settings)
  s.user_target_xcconfig = simulator_arch_settings
end
