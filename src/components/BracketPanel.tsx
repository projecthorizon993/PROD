import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import * as Pro from '../native/ProCamera';

let Slider: any = null; try { Slider = require('@react-native-community/slider').default } catch {}

export function BracketPanel({ onClose }: { onClose: () => void }) {
  const [enabled, setEnabled] = useState(false);
  const [count, setCount] = useState(5);
  const [iso, setIso] = useState(6400);
  const [info, setInfo] = useState<any>(null);

  useEffect(() => { Pro.getBracketInfo().then(v => { setEnabled(v.enabled); setCount(v.count); setIso(v.targetISO); setInfo(v); }).catch(()=>{}); }, []);

  const apply = (en: boolean, c: number, i: number) => {
    setEnabled(en); setCount(c); setIso(i);
    Pro.setBracketMode(en, c, i);
    Pro.getBracketInfo().then(setInfo).catch(()=>{});
  };

  return (
    <View style={s.sheet}>
      <View style={s.head}><Text style={s.title}>Bracketing — Extreme Low Light (0.03 lux)</Text><Pressable onPress={onClose}><Text style={s.close}>✕</Text></Pressable></View>
      <Text style={s.hint}>N× high-ISO stack → effective ISO 2–4× beyond hardware max via burst mean (SNR +10·log10(N) dB). Handheld: Vision translational align (4 ms on ANE) → linear mean (gamma 2.2) → LOE-guarded LowLight ANE. Tripods skip align (0 ms). For 0.03 lux indoor (SID) use 5× @ ISO 6400.</Text>

      <View style={s.row}><Text style={s.label}>Bracketing</Text><Pressable onPress={() => apply(!enabled, count, iso)} style={[s.pill, enabled && s.pillOn]}><Text style={[s.pillTxt, enabled && s.pillTxtOn]}>{enabled ? 'ON' : 'OFF'}</Text></Pressable></View>

      <Text style={s.label}>Frames N: {count} — SNR gain +{(10*Math.log10(count)).toFixed(1)} dB vs single</Text>
      {Slider ? <Slider value={count} minimumValue={3} maximumValue={7} step={1} onValueChange={v=>apply(enabled, Math.round(v), iso)} minimumTrackTintColor="#f5c518" />
      : <View style={s.stepRow}><Pressable onPress={()=>apply(enabled, Math.max(3,count-1), iso)} style={s.step}><Text>-</Text></Pressable><View style={s.track}><View style={[s.fill, {width:`${((count-3)/4)*100}%`}]} /></View><Pressable onPress={()=>apply(enabled, Math.min(7,count+1), iso)} style={s.step}><Text>+</Text></Pressable></View>}
      <View style={s.chipRow}>{[3,5,7].map(n=>(
        <Pressable key={n} onPress={()=>apply(enabled,n,iso)} style={[s.chip, count===n && s.chipOn]}><Text style={[s.chipTxt, count===n && s.chipTxtOn]}>{n}×</Text></Pressable>
      ))}</View>

      <Text style={s.label}>Target effective ISO: {iso} (hardware max ~3200 → stacked)</Text>
      {Slider ? <Slider value={iso} minimumValue={3200} maximumValue={12800} step={800} onValueChange={v=>apply(enabled,count,Math.round(v))} minimumTrackTintColor="#f5c518" />
      : <View style={s.stepRow}><Pressable onPress={()=>apply(enabled,count,Math.max(3200,iso-800))} style={s.step}><Text>-</Text></Pressable><View style={s.track}><View style={[s.fill, {width:`${((iso-3200)/9600)*100}%`}]} /></View><Pressable onPress={()=>apply(enabled,count,Math.min(12800,iso+800))} style={s.step}><Text>+</Text></Pressable></View>}
      <View style={s.chipRow}>{[3200,6400,9600,12800].map(v=>(
        <Pressable key={v} onPress={()=>apply(enabled,count,v)} style={[s.chip, iso===v && s.chipOn]}><Text style={[s.chipTxt, iso===v && s.chipTxtOn]}>{v}</Text></Pressable>
      ))}</View>

      <View style={s.infoBox}>
        <Text style={s.infoTxt}>Current: {enabled? 'ON':'OFF'} · {count}× · ISO {iso} → effective ~{info? Math.round(info.effectiveISO):Math.round(iso/Math.sqrt(count))} (noise as if ISO {info? Math.round(info.effectiveISO):'—'})</Text>
        <Text style={s.infoTxt}>Gain: +{info? info.snrGainDB.toFixed(1): (10*Math.log10(count)).toFixed(1)} dB — extreme low-light PSNR +4–6 dB on SID 0.03 lux vs single.</Text>
        <Text style={s.infoTxt}>Flow: burst &lt;600 ms (HEVC 12 MP) → Vision align 20 ms → linear mean 6 ms → LowLight ANE → sharpen → save. Preview stays single-frame (15 fps).</Text>
      </View>
      <Text style={s.hint}>Tip: For handheld 0.2 lux outdoor (SID 5 lux → 0.2 lux) use 3× @6400; for tripod 0.03 lux indoor use 5–7× @6400–9600. Combine with Night ON (Retinexformer-tiny FP16) for LOE &lt;150.</Text>
    </View>
  );
}
const s = StyleSheet.create({
  sheet:{position:'absolute', bottom:0, left:0, right:0, backgroundColor:'#0f0f0f', padding:12, borderTopLeftRadius:16, borderTopRightRadius:16, borderWidth:1, borderColor:'#333', gap:6, maxHeight:'82%'},
  head:{flexDirection:'row', justifyContent:'space-between', alignItems:'center'},
  title:{color:'#fff', fontWeight:'800', fontSize:12},
  close:{color:'#fff', fontSize:18, padding:6},
  hint:{color:'#666', fontSize:9},
  label:{color:'#ccc', fontSize:11, fontWeight:'700', marginTop:4},
  row:{flexDirection:'row', justifyContent:'space-between', alignItems:'center'},
  pill:{backgroundColor:'#1a1a1a', paddingHorizontal:12, paddingVertical:6, borderRadius:16, borderWidth:1, borderColor:'#333'},
  pillOn:{backgroundColor:'#f5c518', borderColor:'#f5c518'},
  pillTxt:{color:'#aaa', fontSize:11, fontWeight:'700'},
  pillTxtOn:{color:'#000'},
  stepRow:{flexDirection:'row', gap:6, alignItems:'center'},
  step:{width:32, height:32, borderRadius:16, backgroundColor:'#1a1a1a', alignItems:'center', justifyContent:'center', borderWidth:1, borderColor:'#333'},
  track:{flex:1, height:6, backgroundColor:'#222', borderRadius:3},
  fill:{height:6, backgroundColor:'#f5c518', borderRadius:3},
  chipRow:{flexDirection:'row', gap:6, flexWrap:'wrap'},
  chip:{backgroundColor:'#1a1a1a', paddingHorizontal:10, paddingVertical:6, borderRadius:16, borderWidth:1, borderColor:'#333'},
  chipOn:{backgroundColor:'#f5c518', borderColor:'#f5c518'},
  chipTxt:{color:'#aaa', fontSize:11, fontWeight:'700'},
  chipTxtOn:{color:'#000'},
  infoBox:{backgroundColor:'#111', padding:8, borderRadius:10, borderWidth:1, borderColor:'#222', gap:2},
  infoTxt:{color:'#888', fontSize:9},
});
