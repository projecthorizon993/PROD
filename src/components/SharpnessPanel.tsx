import React, { useState } from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import * as Pro from '../native/ProCamera';

let Slider:any=null; try{ Slider=require('@react-native-community/slider').default }catch{}

type Preset='auto'|'psnr'|'perceptual'|'natural'|'balanced';
const PRESET_DESC:Record<Preset,string>={
  auto:'Auto ↔ low-light target',
  psnr:'PSNR/SSIM (fidelity) — mild, protects flat areas',
  perceptual:'LPIPS — stronger, texture-friendly',
  natural:'NIQE/LOE — gentle (no halo)',
  balanced:'Balanced — zoom-adaptive (recommended)',
};

export function SharpnessPanel({ onClose, zoom=1 }:{onClose:()=>void; zoom?:number}){
  const [intensity,setIntensity]=useState(0.55);
  const [preset,setPreset]=useState<Preset>('balanced');
  const apply=(i:number,p:Preset)=>{
    setIntensity(i); setPreset(p);
    Pro.setSharpness(i, p);
  };
  const digital = zoom > 2.2;
  return (
    <View style={s.sheet}>
      <View style={s.head}><Text style={s.title}>Sharpness — Zoom-Aware (MTF/SSIM/NIQE)</Text><Pressable onPress={onClose}><Text style={s.close}>✕</Text></Pressable></View>
      <Text style={s.hint}>Luma-only sharpen (CISharpenLuminance + CIUnsharpMask). Preset tunes radius/intensity for metrics: PSNR (conservative), LPIPS (crisp), NIQE (halo-free). At {zoom.toFixed(1)}× {digital?'digital → +SR + sharpen':'optical → sharpen only'}.</Text>

      <Text style={s.label}>Intensity {intensity.toFixed(2)}</Text>
      {Slider ? <Slider value={intensity} minimumValue={0} maximumValue={1} step={0.02} onValueChange={v=>apply(v, preset)} minimumTrackTintColor="#f5c518" />
      : <View style={s.row}><Pressable onPress={()=>apply(Math.max(0,intensity-0.1),preset)} style={s.step}><Text>−</Text></Pressable>
          <View style={s.track}><View style={[s.fill,{width:`${intensity*100}%`}]} /></View>
          <Pressable onPress={()=>apply(Math.min(1,intensity+0.1),preset)} style={s.step}><Text>+</Text></Pressable></View>
      }

      <Text style={s.label}>Preset</Text>
      {(Object.keys(PRESET_DESC) as Preset[]).map(k=>(
        <Pressable key={k} onPress={()=>apply(intensity,k)} style={[s.presetRow, preset===k && s.presetOn]}>
          <Text style={[s.presetTxt, preset===k && s.presetTxtOn]}>{k.toUpperCase()}</Text>
          <Text style={s.presetDesc}>{PRESET_DESC[k]}</Text>
        </Pressable>
      ))}
      <Text style={s.hint}>Tip: At digital zoom (&gt;2.5×) enable SR in ZoomBar for +3-4 dB PSNR vs pure sharpen. Evaluate: python scripts/evaluate_lowlight.py --output zooms/ --reference gt/</Text>
    </View>
  );
}
const s=StyleSheet.create({
  sheet:{position:'absolute', bottom:0, left:0, right:0, backgroundColor:'#0f0f0f', padding:12, borderTopLeftRadius:16, borderTopRightRadius:16, borderWidth:1, borderColor:'#333', gap:6, maxHeight:'72%'},
  head:{flexDirection:'row', justifyContent:'space-between', alignItems:'center'},
  title:{color:'#fff', fontWeight:'800', fontSize:12},
  close:{color:'#fff', fontSize:18, padding:6},
  hint:{color:'#666', fontSize:9},
  label:{color:'#ccc', fontSize:11, fontWeight:'700', marginTop:4},
  row:{flexDirection:'row', gap:6, alignItems:'center'},
  step:{width:32, height:32, borderRadius:16, backgroundColor:'#1a1a1a', alignItems:'center', justifyContent:'center', borderWidth:1, borderColor:'#333'},
  track:{flex:1, height:6, backgroundColor:'#222', borderRadius:3},
  fill:{height:6, backgroundColor:'#f5c518', borderRadius:3},
  presetRow:{backgroundColor:'#1a1a1a', padding:8, borderRadius:10, borderWidth:1, borderColor:'#222', marginTop:4},
  presetOn:{borderColor:'#f5c518', backgroundColor:'#1f1f0a'},
  presetTxt:{color:'#fff', fontWeight:'700', fontSize:11},
  presetTxtOn:{color:'#f5c518'},
  presetDesc:{color:'#888', fontSize:10, marginTop:2},
});
