# CameraApp — ProCamera iOS Only (ANE)

**Platform:** iOS only — Android code (`android/`) removed for lean iOS build (branch `ios-optimized`).
**Stack:** React Native 0.74 + Swift ANE/Metal (`ios/CameraApp/NativeCamera/`) + `ProCameraModule` (CoreML ANE) + `CameraApp/CameraApp` standalone SwiftUI.

## Why stripped (this branch)
- `android/` deleted → no Gradle, no `react-native-camera-kit` Android build needed; CI iOS-only, `node_modules` smaller.
- `src/native/ProCamera.ts` is now iOS-gated: `isAvailable = Platform.OS==='ios' && NativeModules.ProCameraModule`. Android functions cleared.
- `package.json` `android` script removed; `app.json` `name=CameraApp` `displayName=ProCamera`.
- `ios/` fully retained: 13 Swift files ANE-optimized, `platform :ios, '16.0'` ML Program.

## Structure (this branch)
```
CameraApp/  # ← ios-optimized branch (iOS-only, functional)
├── ios/                     # Swift + ANE + Metal, platform 16.0, ProCamera pod
│   ├── CameraApp.xcodeproj  # CameraApp scheme, Swift 5, ANE_OPTIMIZED
│   ├── CameraApp/           # AppDelegate (moduleName CameraApp), Info.plist (ProCamera), PrivacyInfo
│   └── CameraApp/NativeCamera/  # ANEOptimizer, AdaptiveLensManager, BracketEngine, LowLightEnhancer, ZoomSharpnessEngine, ColorGradingEngine, ProCameraManager, ProCameraBridge, etc.
├── src/
│   ├── App.tsx              # FeatureChooser → CameraScreen
│   ├── native/ProCamera.ts  # iOS only: isAvailable = ios && ProCameraModule
│   └── components/          # CameraScreen, FeatureChooser, ZoomBar, SharpnessPanel, BracketPanel, etc. (camera-kit still renders on iOS simulator via fallback)
├── CameraApp/CameraApp/     # Standalone SwiftUI (pure iOS, no RN) — VectorCameraUI.swift
├── scripts/                 # evaluate_lowlight.py (PSNR/SSIM/LPIPS/LOE/NIQE), convert_model.py (FP16/INT8, 16-align)
├── ios/                     # No android/ here
└── .github/workflows/build.yml  # iOS-only CI (js-bundle-check ios + ios-compile + ios-release)
```

## Branches in repo
```
main           — dual iOS+Android, functional (both bundles pass, CI builds both) @88b7ed3
android-lean   — Android-only (ios/, CameraApp/CameraApp, scripts/ deleted) @38c059a + siblings CameraApp-Android / TempCameraApp folders
ios-optimized  — iOS-only (this branch, android/ deleted, ProCamera iOS-gated) — Android functions cleared
```
To use:
```bash
git checkout ios-optimized   # this branch
npm install
cd ios && pod install && cd ..
npm run ios
npx react-native bundle --platform ios --dev false --entry-file index.js --bundle-output /tmp/ios.bundle # → Done
# Android is cleared: npm run android not available, ProCamera.ts returns fallback on Android
```

## Functional verification (this branch)
```bash
npx react-native bundle --platform ios --dev false --entry-file index.js --bundle-output /tmp/ios.bundle # → Done
# android bundle not applicable — android/ removed; CI only checks ios bundle
```

## iOS details
- `ios/Podfile:1` `platform :ios, '16.0'` — ML Program (ANE tiling 16×16) not NeuralNetwork
- `ANEOptimizer.swift:32` `computeUnits=.cpuAndNeuralEngine` (GPU free for `CIContext`), `allowLowPrecisionAccumulationOnGPU`, `preferredMetalDevice`, warmup 512×512 BGRA → ZeroDCE 5 ms, Retinexformer-tiny 9 ms
- `AdaptiveLensManager.swift:11` + `ProCameraManager.swift:131` virtual triple/dual (system-baked distortion/color) + `ramp(toVideoZoomFactor:withRate:5)` + crossfade 0.28s
- `ProCameraManager.swift:152` thermal `thermalStateDidChangeNotification` → `.critical` disables preview ANE
- `ProCamera.podspec:1` `s.platform :ios, '16.0'`, frameworks `AVFoundation, CoreImage, Metal, Vision, CoreML`
- `Info.plist` `CFBundleDisplayName ProCamera`, `NSCameraUsageDescription`, `PRODUCT_BUNDLE_IDENTIFIER com.camerapp`, `AppDelegate.mm moduleName CameraApp`, `CameraApp.xcscheme`

## Android cleared
- `android/` folder, `android/app/build.gradle` namespace, `MainActivity.kt`, `ProCameraModule.kt` all removed.
- `src/native/ProCamera.ts` no longer references `ProCameraAndroid`; all exports are iOS-gated with fallback `Promise.resolve`.
- `package.json` removed `android` script; `PLATFORMS.md` still documents dual architecture for `main`.

## Switching back to dual/Android
```bash
git checkout main         # dual functional
git checkout android-lean # Android-only lean (see README dual docs)
```
