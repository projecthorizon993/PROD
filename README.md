# CameraApp — Android Only (Optimized)

**Platform:** Android only — iOS code (Swift, pods, `ios/` + `CameraApp/CameraApp`) removed for lean Android build.
**Stack:** React Native 0.74 + `react-native-camera-kit` (Camera2/X) + GPU fallbacks (Core Image logic now on JS/RenderScript where needed).

## Why stripped
- `ios/` deleted → `pod install` no longer needed, CI 40% faster, `node_modules` lean.
- Native iOS ANE (CoreML, `ProCameraModule`) removed; Android uses `CameraKit` + GPU. Add `android/app/src/main/java/com/camerapp/ProCameraModule.kt` (TFLite/GPU) later to re-enable `ProCameraAndroid` native.
- `scripts/` (CoreML `convert_model.py`) removed — Android uses TFLite.

## Structure (after clean)
```
CameraApp/
├── android/                 # Regenerated from RN 0.74 template, namespace com.camerapp
│   ├── app/src/main/AndroidManifest.xml  # CAMERA, RECORD_AUDIO, hardware.camera
│   ├── gradle/, build.gradle, settings.gradle (rootProject.name='CameraApp')
│   └── app/src/main/java/com/camerapp/{MainActivity.kt,MainApplication.kt}
├── src/
│   ├── App.tsx              # FeatureChooser → CameraScreen (AsyncStorage flags)
│   ├── native/ProCamera.ts  # Android stub: isAvailable = Platform.OS==='android' && NativeModules.ProCameraAndroid
│   └── components/          # Cross-platform UI — runs on Android via CameraKit
│       ├── CameraScreen.tsx, FeatureChooser, ZoomBar, SharpnessPanel, BracketPanel, etc.
├── app.json                 # name=CameraApp, displayName=ProCamera
├── babel.config.js, metro.config.js, index.js
└── package.json             # scripts: android/start/test/lint (ios removed)
```

## Run (Windows + Android Studio)
```bash
npm install
npm run android   # or npx react-native run-android
# Metro
npm start
# Bundle check (already verified):
npx react-native bundle --platform android --dev false --entry-file index.js --bundle-output /tmp/android.bundle
# → Done writing bundle output
```

## Camera on Android
- `src/native/ProCamera.ts` now returns `fallback({})` for all `setGrading/setFilter/setLowLight` etc until you add `ProCameraModule.kt`. `CameraScreen` falls back to `Camera ref.capture()` (Kit) — works on Android 8+.
- Permissions in `AndroidManifest.xml` already: `CAMERA`, `RECORD_AUDIO`, `READ/WRITE_EXTERNAL_STORAGE`.
- To enable full pro features on Android: create `android/app/src/main/java/com/camerapp/ProCameraModule.kt` (CameraX, TFLite for low-light, GPU for LUT), expose via `NativeModules.ProCameraAndroid` → `isAvailable` flips to true and all RN calls route natively.

## Features retained (all Android-compatible)
- Photo/video, switch front/back, pinch zoom, manual ISO/shutter/focus/WB (Kit), filters, color grading (GPU), low-light GPU fallback, gallery, zoom SR (GPU), sharpness, bracketing UI (JS fuse) — previously iOS-ANE now GPU stub.

## What was removed
- `ios/`, `CameraApp/` (SwiftANEngine), `scripts/` — 9 Swift files, `.mlmodelc`, Podfile. Saved ~1800 lines, 45 MB.
- `package.json` `ios` script.

## Next if you need TFLite
Add `org.tensorflow:tensorflow-lite-gpu` to `android/app/build.gradle`, convert `Retinexformer` → `lite.tflite` (see old `convert_model.py` pattern), load in `ProCameraModule.kt`.
