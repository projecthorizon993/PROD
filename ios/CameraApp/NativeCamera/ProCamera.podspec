Pod::Spec.new do |s|
  s.name                   = "ProCamera"
  s.version                = "1.0.0"
  s.summary                = "ProCamera AVFoundation + Core Image + ANE low-light"
  s.homepage               = "https://example.com"
  s.license                = "MIT"
  s.author                 = { "ProCamera" => "pro@example.com" }
  s.platform               = :ios, "16.0"
  s.source                 = { :path => "." }
  s.source_files           = "*.{swift,h,m}"
  s.requires_arc           = true
  s.swift_version          = "5.0"
  s.dependency "React-Core"
  s.frameworks = "AVFoundation", "CoreImage", "Metal", "MetalPerformanceShaders", "Vision", "CoreML", "Accelerate"
  s.pod_target_xcconfig = { "OTHER_SWIFT_FLAGS" => "-DANE_OPTIMIZED" }
end
