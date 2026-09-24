const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, '..', 'node_modules', 'react-native-camera-kit', 'ios', 'ReactNativeCameraKit', 'RealCamera.swift');

if (!fs.existsSync(file)) {
  console.log('[patch] RealCamera.swift not found, skipping');
  process.exit(0);
}

let src = fs.readFileSync(file, 'utf8');
const original = src;

// Patch 1: isDeferredStart API is iOS 26+ not in Xcode 15.4 SDK (iOS 17.5) - make no-op
if (src.includes('isDeferredStartSupported')) {
  src = src.replace(
    /private func applyDeferredStartConfiguration\(\) \{[\s\S]*?if metadataOutput\.isDeferredStartSupported[\s\S]*?\n    \}/m,
    `private func applyDeferredStartConfiguration() {
        return
    }`
  );
  // fallback if regex didn't match, simple replace
  if (src.includes('isDeferredStartSupported')) {
    src = src.replace(/isDeferredStartSupported/g, 'isDeferredStartSupported_DISABLED');
    src = src.replace(/isDeferredStartEnabled/g, 'isDeferredStartEnabled_DISABLED');
  }
  console.log('[patch] Patched RealCamera.swift isDeferredStart');
}

if (src !== original) {
  fs.writeFileSync(file, src, 'utf8');
  console.log('[patch] RealCamera.swift patched successfully');
} else {
  console.log('[patch] No changes needed');
}
