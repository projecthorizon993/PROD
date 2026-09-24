# CameraApp — ProCamera (iOS ANE + Android CameraX)

**Platforms:** iOS (ANE/Metal, `ios/`) + Android (CameraX/CameraKit, `android/`) — one React Native project, separated native code (see `PLATFORMS.md:1`).
**Stack:** React Native 0.74 + `react-native-camera-kit` + `ProCameraModule` (Swift ANE) / `ProCameraAndroid` (Kotlin stub with TFLite hook).

## Functional Builds (verified)

```bash
npm install
npx react-native bundle --platform ios --dev false --entry-file index.js --bundle-output /tmp/ios.bundle      # → Done
npx react-native bundle --platform android --dev false --entry-file index.js --bundle-output /tmp/android.bundle # → Done
```

- **Android:** `android/app/build.gradle:1` `namespace com.camerapp`, `applicationId com.camerapp` ↔ `android/app/src/main/java/com/camerapp/MainActivity.kt:1` `package com.camerapp`. `AndroidManifest.xml:1` has `CAMERA`, `RECORD_AUDIO`, `READ_MEDIA_IMAGES/VIDEO`, `hardware.camera`. Native stub `ProCameraModule.kt` + `ProCameraPackage.kt` wired in `MainApplication.kt:20` → `NativeModules.ProCameraAndroid` available. `src/native/ProCamera.ts:1` dual-gates to `ProCameraAndroid` or `ProCameraModule`.
- **iOS:** `ios/Podfile:1` `platform :ios, '16.0'`, `ProCamera` pod at `ios/CameraApp/NativeCamera/ProCamera.podspec:1`, 13 Swift files, `CameraApp.xcscheme` renamed from HelloWorld, `PRODUCT_BUNDLE_IDENTIFIER com.camerapp`, `IPHONEOS_DEPLOYMENT_TARGET 16.0`, `Info.plist` `CFBundleDisplayName ProCamera`, `AppDelegate.mm:9` `moduleName CameraApp`. CI `ios-compile` job builds unsigned `iphoneos` with `CODE_SIGNING_ALLOWED=NO`.

## Structure
```
CameraApp/  # ← main branch (dual platform, functional)
├── android/                 # CameraX, Gradle 8, namespace com.camerapp
│   ├── app/src/main/AndroidManifest.xml  # CAMERA, RECORD_AUDIO, hardware.camera
│   └── app/src/main/java/com/camerapp/{MainActivity.kt,MainApplication.kt,ProCameraModule.kt,ProCameraPackage.kt}
├── ios/                     # Swift + ANE + Metal, platform 16.0, ProCamera pod
│   ├── CameraApp.xcodeproj  # CameraApp scheme, Swift 5, ANE_OPTIMIZED
│   └── CameraApp/NativeCamera/  # ANEOptimizer, AdaptiveLensManager, BracketEngine, LowLightEnhancer, ZoomSharpnessEngine, etc.
├── src/
│   ├── App.tsx              # FeatureChooser → CameraScreen
│   ├── native/ProCamera.ts  # Dual gate: android ProCameraAndroid / ios ProCameraModule
│   └── components/          # CameraScreen, FeatureChooser, ZoomBar, SharpnessPanel, BracketPanel, etc.
├── CameraApp/CameraApp/     # Standalone SwiftUI (pure iOS, no RN)
├── scripts/                 # evaluate_lowlight.py (PSNR/SSIM/LPIPS/LOE/NIQE), convert_model.py (FP16/INT8)
├── .github/workflows/build.yml  # js-bundle-check + android + ios-compile + ios-release
└── app.json                 # name=CameraApp, displayName=ProCamera

CameraApp-Android/  # ← sibling folder copy of branch android-lean (Android-only, lean)
├── android/         # Same as above, but NO ios/, NO scripts/, NO CameraApp/CameraApp
├── src/             # Same UI, ProCamera.ts android-only (isAvailable = android && ProCameraAndroid)
├── .github/workflows/build.yml  # Android-only CI (js-bundle-check + android)
└── README.md        # Android-only docs
```

## Branches

- `main` — dual iOS+Android, functional (both bundles pass, CI builds both).
- `android-lean` — Android-only ( `ios/`, `CameraApp/CameraApp`, `scripts/` deleted). `src/native/ProCamera.ts` → `isAvailable = android && ProCameraAndroid`. Native stub `ProCameraModule.kt` already present. `package.json` `ios` script removed. CI is android-only. Created from `main@a987645`.

To use lean:
```bash
git checkout android-lean
npm install
npm run android
# or use sibling folder copy:
cd ../CameraApp-Android
npm install
npm run android
```

## Run

```bash
# Both platforms share JS, native is separated
npm install

# iOS (macOS, Xcode 15.4, ANE, Metal, 60fps, thermal)
cd ios && pod install && cd ..   # platform 16.0, ProCamera pod auto-compiles Swift
npm run ios      # or npx react-native run-ios
npx react-native bundle --platform ios --dev false --entry-file index.js --bundle-output /tmp/ios.bundle

# Android (Windows + Android Studio, CameraKit + GPU fallback, no ANE needed for stub)
npm run android  # or npx react-native run-android
npx react-native bundle --platform android --dev false --entry-file index.js --bundle-output /tmp/android.bundle
```

## Android native extension

- `ProCameraModule.kt` stub already returns `fallback({})` for all RN calls so `isAvailable` flips to true and UI shows native path. Replace with real CameraX + TFLite: add `org.tensorflow:tensorflow-lite-gpu` to `android/app/build.gradle`, convert `Retinexformer` → `lite.tflite` (see `scripts/convert_model.py` pattern on `main`), load in `ProCameraModule.kt`.

## iOS notes

- `ios/Podfile` `platform :ios, '16.0'` — ML Program (ANE tiling 16×16).
- `ANEOptimizer.swift:32` `computeUnits=.cpuAndNeuralEngine` (GPU free for `CIContext`), `allowLowPrecisionAccumulationOnGPU`, `preferredMetalDevice`, warmup 512×512.
- `AdaptiveLensManager.swift:11` + `ProCameraManager.swift:131` virtual triple/dual + `ramp(toVideoZoomFactor:withRate:5)` + crossfade 0.28s.
- `ProCameraManager.swift:152` thermal `thermalStateDidChangeNotification` → `.critical` disables preview ANE.
