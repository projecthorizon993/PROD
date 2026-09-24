import React from 'react';
import { View, Text, Switch, StyleSheet, ScrollView, Pressable } from 'react-native';

export type FeatureFlags = {
  photo: boolean;
  video: boolean;
  cameraSwitch: boolean;
  manual: boolean;
  filters: boolean;
  colorGrading: boolean;
  lowLightANE: boolean;
  gallery: boolean;
  zoom: boolean;
  sharpness: boolean;
  bracketing: boolean;
};

export const defaultFlags: FeatureFlags = {
  photo: true,
  video: true,
  cameraSwitch: true,
  manual: true,
  filters: true,
  colorGrading: true,
  lowLightANE: true,
  gallery: true,
  zoom: true,
  sharpness: true,
  bracketing: false,
};

const DESCR: Record<keyof FeatureFlags, string> = {
  photo: 'Photo capture (HEVC/high-res, flash, stabilization)',
  video: 'Video recording (4K, stabilization, mic)',
  cameraSwitch: 'Front/back switch + pinch zoom',
  manual: 'Manual ISO / shutter / focus / WB / exposure bias',
  filters: 'Filters (Mono, Vivid, Cinematic, Teal&Orange …)',
  colorGrading: 'Live color grading (exposure/contrast/sat/temp/tint/shadows/highlights + LUT .cube from other project)',
  lowLightANE: 'Enhanced low-light via Neural Engine (CoreML ANE + MPS fallback, throttled 15fps, retinex+Zero-DCE+SNR, LOE/NIQE guard)',
  gallery: 'Gallery/preview + save to Photo Library',
  zoom: 'Zoom (optical + digital super-resolution via ANE RealESRGAN-tiny/SwinIR, Lanczos fallback)',
  sharpness: 'Sharpness optimizing (luma-only unsharp, metric-aware: PSNR/SSIM vs LPIPS vs NIQE, zoom-adaptive)',
  bracketing: 'Extreme low-light bracketing — N× high-ISO stack (effective ISO 2–4× max, 0.03 lux SID) via BracketEngine, Vision align + mean fuse, feeds LowLight ANE',
};

export function FeatureChooser({ value, onChange, onDone }: { value: FeatureFlags; onChange: (v: FeatureFlags)=>void; onDone: ()=>void }) {
  return (
    <View style={s.wrap}>
      <Text style={s.title}>ProCamera — Choose your features</Text>
      <Text style={s.sub}>Toggle what you want. App will hide disabled features (you can re-open this chooser from the camera screen).</Text>
      <ScrollView style={{flex:1}} contentContainerStyle={{paddingBottom: 16}}>
        { (Object.keys(value) as (keyof FeatureFlags)[]).map(k => (
          <View key={k} style={s.row}>
            <View style={{flex:1}}>
              <Text style={s.label}>{k}</Text>
              <Text style={s.desc}>{DESCR[k]}</Text>
            </View>
            <Switch value={value[k]} onValueChange={v => onChange({...value, [k]: v})} />
          </View>
        ))}
        <View style={s.hint}>
          <Text style={s.hintText}>Tip: "other project" LUTs → drop .cube files in app Documents and use Load LUT button in Grading panel. ANE model → add LowLightRawML.mlmodelc to Xcode bundle (any custom denoiser/low-light UNet) — engine auto-detects it.</Text>
        </View>
      </ScrollView>
      <Pressable style={s.cta} onPress={onDone}><Text style={s.ctaText}>Start Camera →</Text></Pressable>
    </View>
  );
}

const s = StyleSheet.create({
  wrap:{flex:1, backgroundColor:'#0a0a0a', paddingTop:56, paddingHorizontal:16},
  title:{color:'#fff', fontSize:22, fontWeight:'800'},
  sub:{color:'#aaa', marginTop:6, marginBottom:12},
  row:{flexDirection:'row', alignItems:'center', backgroundColor:'#1a1a1a', padding:12, borderRadius:12, marginBottom:8},
  label:{color:'#fff', fontWeight:'700', textTransform:'capitalize'},
  desc:{color:'#999', fontSize:12, marginTop:2},
  hint:{backgroundColor:'#111', borderWidth:1, borderColor:'#333', padding:10, borderRadius:10, marginTop:8},
  hintText:{color:'#888', fontSize:11},
  cta:{backgroundColor:'#fff', padding:14, borderRadius:14, alignItems:'center', marginBottom:20, marginTop:8},
  ctaText:{color:'#000', fontWeight:'800', fontSize:16},
});
