import React, { useState } from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import Slider from '@react-native-community/slider';
import * as Pro from '../native/ProCamera';

// Lightweight slider - if community slider not installed, fallback to pressable steps
let RNSlider: any = null;
try { RNSlider = require('@react-native-community/slider').default; } catch {}

function FallbackSlider({value, onChange, min, max}:{value:number; onChange:(v:number)=>void; min:number; max:number}){
  return <View style={{flexDirection:'row', gap:6, alignItems:'center'}}>
    <Pressable onPress={()=> onChange(Math.max(min, value-(max-min)/10))} style={s.step}><Text>-</Text></Pressable>
    <View style={{flex:1, height:6, backgroundColor:'#333', borderRadius:3}}><View style={{width:`${((value-min)/(max-min))*100}%`, height:6, backgroundColor:'#fff', borderRadius:3}}/></View>
    <Pressable onPress={()=> onChange(Math.min(max, value+(max-min)/10))} style={s.step}><Text>+</Text></Pressable>
  </View>;
}

export function ManualControls({ onClose }:{onClose:()=>void}){
  const [iso, setIso] = useState(200);
  const [shutterMs, setShutterMs] = useState(8);
  const [focus, setFocus] = useState(0.5);
  const [r,setR]=useState(1),[g,setG]=useState(1),[b,setB]=useState(1);

  const applyExposure = (nIso:number, nShut:number)=>{ setIso(nIso); setShutterMs(nShut); if(Pro.isAvailable) Pro.setManualExposure(nIso, nShut); };
  const applyFocus = (v:number)=>{ setFocus(v); Pro.isAvailable && Pro.setManualFocus(v); };
  const applyWB = (nr:number,ng:number,nb:number)=>{ setR(nr); setG(ng); setB(nb); Pro.isAvailable && Pro.setWhiteBalance(nr,ng,nb); };

  const SliderComp = RNSlider ? RNSlider : FallbackSlider;

  return (
    <View style={s.sheet}>
      <View style={s.head}><Text style={s.title}>Manual (ANE-aware)</Text><Pressable onPress={onClose}><Text style={s.close}>✕</Text></Pressable></View>

      <Text style={s.label}>ISO {iso.toFixed(0)}  — double-tap Auto to reset</Text>
      {RNSlider ? <RNSlider value={iso} minimumValue={32} maximumValue={3200} step={10} onValueChange={(v:number)=>applyExposure(v, shutterMs)} minimumTrackTintColor="#fff" /> : <FallbackSlider value={iso} min={32} max={3200} onChange={v=>applyExposure(v,shutterMs)} />}
      <Pressable onPress={()=>{ Pro.isAvailable && Pro.setManualExposure(0,0); setIso(200);}} style={s.auto}><Text style={s.autoTxt}>Auto ISO/Shutter</Text></Pressable>

      <Text style={s.label}>Shutter {shutterMs.toFixed(1)} ms</Text>
      {RNSlider ? <RNSlider value={shutterMs} minimumValue={0.5} maximumValue={33} onValueChange={(v:number)=>applyExposure(iso,v)} /> : <FallbackSlider value={shutterMs} min={0.5} max={33} onChange={v=>applyExposure(iso,v)} />}

      <Text style={s.label}>Focus {focus.toFixed(2)} (0 near — 1 far)</Text>
      {RNSlider ? <RNSlider value={focus} minimumValue={0} maximumValue={1} onValueChange={applyFocus} /> : <FallbackSlider value={focus} min={0} max={1} onChange={applyFocus} />}

      <Text style={s.label}>White Balance R {r.toFixed(2)} G {g.toFixed(2)} B {b.toFixed(2)}</Text>
      <View style={{flexDirection:'row', gap:8}}>
        <View style={{flex:1}}><Text style={s.sub}>R</Text>{RNSlider ? <RNSlider value={r} minimumValue={1} maximumValue={3} onValueChange={v=>applyWB(v,g,b)}/> : <FallbackSlider value={r} min={1} max={3} onChange={v=>applyWB(v,g,b)}/>}</View>
        <View style={{flex:1}}><Text style={s.sub}>G</Text>{RNSlider ? <RNSlider value={g} minimumValue={1} maximumValue={3} onValueChange={v=>applyWB(r,v,b)}/> : <FallbackSlider value={g} min={1} max={3} onChange={v=>applyWB(r,v,b)}/>}</View>
        <View style={{flex:1}}><Text style={s.sub}>B</Text>{RNSlider ? <RNSlider value={b} minimumValue={1} maximumValue={3} onValueChange={v=>applyWB(r,g,v)}/> : <FallbackSlider value={b} min={1} max={3} onChange={v=>applyWB(r,g,v)}/>}</View>
      </View>
      <Pressable onPress={()=> Pro.isAvailable && Pro.setWhiteBalance(1,1,1)} style={s.auto}><Text style={s.autoTxt}>Auto WB</Text></Pressable>

      <Text style={s.hint}>Manual changes hit ProCameraManager (AVFoundation). Exposure uses setExposureModeCustom (ISO + duration) — ANE low-light auto-pauses while manual is locked.</Text>
    </View>
  );
}
const s=StyleSheet.create({
  sheet:{position:'absolute', bottom:0, left:0, right:0, backgroundColor:'#111', padding:14, borderTopLeftRadius:16, borderTopRightRadius:16, borderWidth:1, borderColor:'#333', gap:6, maxHeight:'62%'},
  head:{flexDirection:'row', justifyContent:'space-between', alignItems:'center'},
  title:{color:'#fff', fontWeight:'800'},
  close:{color:'#fff', fontSize:18, padding:6},
  label:{color:'#ccc', fontSize:12, marginTop:6},
  sub:{color:'#888', fontSize:11},
  auto:{alignSelf:'flex-start', backgroundColor:'#222', paddingHorizontal:10, paddingVertical:6, borderRadius:10, marginTop:4, borderWidth:1, borderColor:'#333'},
  autoTxt:{color:'#fff', fontSize:11, fontWeight:'600'},
  hint:{color:'#666', fontSize:10, marginTop:6},
  step:{width:32, height:32, borderRadius:16, backgroundColor:'#222', alignItems:'center', justifyContent:'center', borderWidth:1, borderColor:'#333'},
});
