import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, Pressable, ScrollView } from 'react-native';
import * as Pro from '../native/ProCamera';

let Slider:any=null; try{ Slider=require('@react-native-community/slider').default }catch{}

export function ZoomBar({ zoom, onZoom, onSuperResToggle }: { zoom:number; onZoom:(z:number)=>void; onSuperResToggle?:(v:boolean)=>void }) {
  const [range, setRange] = useState({min:1,max:8,opticalThreshold:2.5,activeLens:'wide',seamless:true,switchFactors:[1]});
  const [sr, setSr] = useState(true);
  useEffect(()=>{ Pro.getZoomInfo().then((r:any)=> setRange(r)).catch(()=>{}); },[]);
  const isDigital = zoom > range.opticalThreshold * 0.9;
  const lensLabel = (range as any).activeLens ? `${(range as any).activeLens} ${range.seamless ? '· seamless bake ON' : '· seamless OFF'}` : '';
  return (
    <View style={s.wrap}>
      <View style={s.head}>
        <Text style={s.label}>Zoom {zoom.toFixed(1)}× {isDigital ? '· DIGITAL + ANE SR' : '· OPTICAL'} · {lensLabel}</Text>
        <View style={{flexDirection:'row', gap:6}}>
          <Pressable onPress={async()=>{ const v=!range.seamless; await Pro.setSeamlessEnabled(v); setRange((r:any)=>({...r, seamless:v})); }} style={[s.srBtn, (range as any).seamless && s.srOn]}>
            <Text style={[s.srTxt, (range as any).seamless && s.srTxtOn]}>{(range as any).seamless ? 'Seamless ON' : 'Seamless OFF'}</Text>
          </Pressable>
          <Pressable onPress={()=>{ const v=!sr; setSr(v); Pro.setSuperResolution(v); onSuperResToggle?.(v); }} style={[s.srBtn, sr&&s.srOn]}>
            <Text style={[s.srTxt, sr&&s.srTxtOn]}>{sr? 'SR ON':'SR OFF'}</Text>
          </Pressable>
        </View>
      </View>
      {Slider ? <Slider value={zoom} minimumValue={range.min} maximumValue={range.max} step={0.1} onValueChange={onZoom} minimumTrackTintColor={isDigital ? '#f5c518':'#fff'} maximumTrackTintColor="#333" thumbTintColor="#fff" />
      : <View style={s.fallbackRow}>
          <Pressable onPress={()=>onZoom(Math.max(range.min, zoom-0.5))} style={s.step}><Text style={s.stepTxt}>−</Text></Pressable>
          <View style={s.track}><View style={[s.fill, {width:`${((zoom-range.min)/(range.max-range.min))*100}%`, backgroundColor: isDigital?'#f5c518':'#fff'}]} /></View>
          <Pressable onPress={()=>onZoom(Math.min(range.max, zoom+0.5))} style={s.step}><Text style={s.stepTxt}>+</Text></Pressable>
        </View>
      }
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.presets}>
        {(() => {
          const info: any = range as any;
          const lenses = info.lensesBack as {id:string,label:string,nominal:number}[] | undefined;
          const presets = lenses && lenses.length>0 ? lenses.map(l=>l.nominal) : ([1,2,5,8] as number[]);
          // Also add ultraWide 0.5 if present, else fallback
          const uniq = Array.from(new Set<number>([...presets, ...((info.switchFactors as number[])||[])] )).filter(v=>v<=range.max+0.05 && v>=0.4).sort((a,b)=>a-b);
          const show = uniq.length ? uniq : [1,2,5,8].filter(v=>v<=range.max+0.01);
          return show.map(v=>(
            <Pressable key={v} onPress={()=>onZoom(v)} style={[s.preset, Math.abs(zoom-v)<0.12 && s.presetOn]}><Text style={[s.presetTxt, Math.abs(zoom-v)<0.12 && s.presetTxtOn]}>{v===0.5?'0.5×':v+'×'}</Text></Pressable>
          ));
        })()}
      </ScrollView>
      <Text style={s.hint}>Adaptive lens: {(range as any).lensesBack ? JSON.stringify((range as any).lensesBack.map((l:any)=>l.label)) : 'discovering…'} · System bake: {(range as any).isSeamlessAvailable ? 'virtual-device seamless (no cut)' : 'manual fallback + 0.28s crossfade (SE/iPad)'} · Seamless ON ramps @ {JSON.stringify((range as any).switchFactors)}.</Text>
    </View>
  );
}
const s=StyleSheet.create({
  wrap:{backgroundColor:'#0f0f0f', padding:10, borderRadius:12, borderWidth:1, borderColor:'#333', gap:6},
  head:{flexDirection:'row', justifyContent:'space-between', alignItems:'center'},
  label:{color:'#fff', fontWeight:'700', fontSize:11},
  srBtn:{backgroundColor:'#1a1a1a', paddingHorizontal:8, paddingVertical:4, borderRadius:12, borderWidth:1, borderColor:'#333'},
  srOn:{backgroundColor:'#f5c518', borderColor:'#f5c518'},
  srTxt:{color:'#aaa', fontSize:10, fontWeight:'700'},
  srTxtOn:{color:'#000'},
  fallbackRow:{flexDirection:'row', alignItems:'center', gap:6},
  step:{width:32, height:32, borderRadius:16, backgroundColor:'#1a1a1a', alignItems:'center', justifyContent:'center', borderWidth:1, borderColor:'#333'},
  stepTxt:{color:'#fff', fontSize:16},
  track:{flex:1, height:6, backgroundColor:'#222', borderRadius:3},
  fill:{height:6, borderRadius:3},
  presets:{gap:6},
  preset:{backgroundColor:'#1a1a1a', paddingHorizontal:10, paddingVertical:6, borderRadius:16, borderWidth:1, borderColor:'#333'},
  presetOn:{backgroundColor:'#fff', borderColor:'#fff'},
  presetTxt:{color:'#aaa', fontSize:11, fontWeight:'700'},
  presetTxtOn:{color:'#000'},
  hint:{color:'#666', fontSize:9},
});
