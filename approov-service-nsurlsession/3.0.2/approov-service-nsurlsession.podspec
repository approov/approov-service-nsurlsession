Pod::Spec.new do |s|
  s.name         = "approov-service-nsurlsession"
  s.version      = "3.0.2"
  s.summary      = "ApproovSDK iOS framework"
  s.description  = <<-DESC
                  Approov mobile attestation framework for iOS
                   DESC
  s.homepage     = "https://approov.io"
  # brief license entry:
  s.license      = "https://approov.io/terms"
  s.authors      = { "CriticalBlue, Ltd." => "support@approov.io" }
  s.platform     = :ios
  s.source       = { :git => "https://github.com/approov/approov-service-nsurlsession.git", :tag => "#{s.version}" }
  s.source_files = 'ApproovNSURLSession.{h,m}', 'ApproovService.{h,m}', 'ApproovPinningURLSessionDelegate.{h,m}', 'ApproovSessionTaskObserver.{h,m}', 'RSSwizzle.{h,m}'
  s.ios.deployment_target  = '10.0'
  s.pod_target_xcconfig = { 'VALID_ARCHS' => 'arm64 armv7 x86_64' }
  s.dependency 'approov-ios-sdk', '~> 3.0.0'
end
