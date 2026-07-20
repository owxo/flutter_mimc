Pod::Spec.new do |s|
  s.name             = 'flutter_mimc'
  s.version          = '2.0.0-dev.2'
  s.summary          = 'Desktop FFI implementation of the Flutter MIMC plugin.'
  s.description      = 'Xiaomi MIMC desktop bridge for macOS.'
  s.homepage         = 'https://github.com/owxo/flutter_mimc'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'flutter_mimc contributors' => 'mimc-help@xiaomi.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.vendored_libraries = 'Vendor/*.dylib' unless Dir[File.join(__dir__, 'Vendor/*.dylib')].empty?
  s.resource_bundles = {
    'flutter_mimc_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'DEFINES_MODULE' => 'YES'
  }
end
