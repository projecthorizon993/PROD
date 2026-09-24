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
  // Robust replace: replace entire function body with no-op
  const before = src;
  src = src.replace(
    /private func applyDeferredStartConfiguration\(\) \{[\s\S]*?\n    \}/,
    `private func applyDeferredStartConfiguration() {
        return
    }`
  );
  if (src === before) {
    // Fallback: simple string replace of the whole function if regex failed
    const startIdx = src.indexOf('private func applyDeferredStartConfiguration()');
    if (startIdx !== -1) {
      const endIdx = src.indexOf('\n    }', startIdx);
      if (endIdx !== -1) {
        src = src.slice(0, startIdx) + `private func applyDeferredStartConfiguration() {
        return
    }` + src.slice(endIdx + 5);
      }
    }
  }
  // If still contains the symbols, force rename to prevent compile error
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
