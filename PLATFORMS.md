# Platforms — Separated iOS vs Android

This repo is **one React Native project with fully separated native code** — no shared Swift/Kotlin mix.

## Structure

```
CameraApp/
├── android/                 # Android only — CameraX via react-native-camera-kit, Gradle 8, namespace com.camerapp
│   ├── app/src/main/java/com/camerapp/MainActivity.kt
│   └── app/src/main/AndroidManifest.xml  # CAMERA, RECORD_AUDIO
├── ios/                     # iOS only — Swift + ANE + Metal, platform 16.0, ProCamera pod
│   ├── CameraApp.xcodeproj  # Renamed from HelloWorld, Swift 5, ANE_OPTIMIZED
│   ├── CameraApp/           # AppDelegate, Info.plist (camera/mic/photo perms)
│   └── CameraApp/NativeCamera/  # 13 Swift files, all ANE-optimized
│       ├── ANEOptimizer.swift, AdaptiveLensManager.swift, BracketEngine.swift
│       ├── LowLightEnhancer.swift (Retinex + SNR + Zero-DCE + HVI, 512 FP16, warmup)
│       ├── ZoomSharpnessEngine.swift (RealESRGAN-tiny 2×, 12 ms ANE)
│       ├── ColorGradingEngine.swift (CIColorCube .cube 17/32/33/64, mixKernel, bake)
│       ├── ProCameraManager.swift (seamless virtual-device + crossfade, thermal throttle)
│       └── ProCameraBridge.swift/.m, LowLightMetrics.swift, FilterPipeline.swift, ...
├── src/
│   ├── App.tsx              # Shared entry, FeatureChooser → CameraScreen, AsyncStorage flags
│   ├── native/ProCamera.ts  # Platform gate: isAvailable = iOS && NativeModules.ProCameraModule
│   └── components/          # Cross-platform UI; iOS uses ANE path, Android GPU fallback
├── CameraApp/CameraApp/     # Standalone SwiftUI (pure iOS, no RN) — ProCameraSwiftUI.swift
└── scripts/                 # iOS ANE tools: evaluate_lowlight.py (PSNR/SSIM/LPIPS/LOE/NIQE), convert_model.py (FP16/INT8, 16-align)
```

## How to run

```bash
# Both platforms share JS, native is separated
npm install

# iOS (optimized first — ANE, Metal, 60fps, thermal)
cd ios && pod install && cd ..   # platform 16.0, ProCamera pod auto-compiles Swift
npm run ios      # or npx react-native run-ios
# Verify bundle
npx react-native bundle --platform ios --dev false --entry-file index.js --bundle-output /tmp/ios.bundle

# Android (CameraKit + GPU fallback, no ANE)
npm run android  # or npx react-native run-android
npx react-native bundle --platform android --dev false --entry-file index.js --bundle-output /tmp/android.bundle
```

## iOS — Optimized to run as good as possible (priority)

- **Podfile** `ios/Podfile:1` `platform :ios, '16.0'` — ML Program (ANE tiling 16×16) not NeuralNetwork
- **ANE** `ANEOptimizer.swift:32` `computeUnits=.cpuAndNeuralEngine` (GPU free for `CIContext` grading), `allowLowPrecisionAccumulationOnGPU`, `preferredMetalDevice`, `warmup` 512×512 BGRA → steady ZeroDCE 5 ms, Retinexformer-tiny 9 ms
- **Seamless** `AdaptiveLensManager.swift:11` + `ProCameraManager.swift:131` virtual triple/dual (system-baked distortion/color) + `ramp(toVideoZoomFactor:withRate:5)` + crossfade 0.28s
- **Thermal** `ProCameraManager.swift:152` `ProcessInfo.thermalStateDidChangeNotification` → `.critical` disables preview ANE
- **Metal** `ColorGradingEngine` fused `lggKernel` + `mixKernel` + `CIColorCube` (GPU), `LowLight` 15 fps throttled, `CIContext(mtlDevice:)`
- **Repair** All 13 Swift files restored, `Podfile` ProCamera pod, `Info.plist` perms, `CameraApp.xcodeproj` renamed.

## Android — Separated, lean

- `android/` regenerated from `template/android`, `com.helloworld→com.camerapp`, perms added, `ProCamera.ts` stub returns fallback on Android (`isAvailable` false until you add `ProCameraModule.kt` with TFLite/GPU).
- No iOS Swift files are bundled on Android (Metro platform filter).

## Switching versions

No branch needed — `Platform.OS` gates at runtime. To work purely on iOS: `npm run ios`; purely Android: `npm run android`. For fully isolated builds, `git checkout -b ios-optimized` / `android-lean` if you want.
