Pod::Spec.new do |s|
    s.name         = "approov-service-nsurlsession"
    s.module_name  = "approov_service_nsurlsession"
    s.version      = "dev"
    s.summary      = "Approov mobile attestation SDK"
    s.description  = <<-DESC
      Approov SDK integrates security attestation and secure string fetching for both iOS and watchOS apps.
    DESC
    s.homepage     = "https://approov.io"
    s.license      = { :type => "MIT", :file => "LICENSE" }
    s.authors      = { "CriticalBlue, Ltd." => "support@approov.io" }
    s.source       = { :git => "https://github.com/approov/approov-service-nsurlsession.git", :tag => "#{s.version}" }

    # Supported platforms
    s.ios.deployment_target = '11.0'
    s.watchos.deployment_target = '9.0'

    # Specify the source code paths for the combined target
    s.source_files = [
      'Sources/ApproovNSURLSessionObjC/**/*.{h,m}',
      'Sources/ApproovNSURLSession/**/*.{swift}'
    ]
    s.swift_version = '5.0'
    s.static_framework = true

    # Dependency on the Approov SDK
    s.dependency 'approov-ios-sdk', '~> 3.5.3'
    s.frameworks = 'Approov'
    s.dependency 'swift-http-structured-headers', '~> 1.4.0'

    # Pod target xcconfig settings if required
    s.pod_target_xcconfig = {
      'VALID_ARCHS' => 'arm64 x86_64 arm64_32 x86_64',
      'DEFINES_MODULE' => 'YES',
      'SWIFT_INCLUDE_PATHS' => '$(PODS_ROOT)/Target Support Files/swift-http-structured-headers'
    }
  end
