import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import * as Pro from '../native/ProCamera';

type Target = 'psnr'|'perceptual'|'natural'|'balanced';
type Strategy = 'auto'|'aneRetinexformer'|'aneZeroDCE'|'retinexFallback'|'hviFallback';

const TARGET_DESC: Record<Target,string> = {
  psnr: 'PSNR/SSIM (fidelity) — best on LOL/SID paired',
  perceptual: 'LPIPS (perceptual) — textures, avoids blur',
  natural: 'NIQE/LOE (natural) — light order, no halos',
  balanced: 'Balanced (recommended) — PSNR+LOE/NIQE trade-off',
};
const STRATEGY_DESC: Record<Strategy,string> = {
  auto: 'Auto — pick ANE Retinexformer if present, else Retinex+ZeroDCE',
  aneRetinexformer: 'ANE Retinexformer/HVI (2023-2025 SOTA, ~27-28 dB PSL)',
  aneZeroDCE: 'ANE Zero-DCE++ (90K, fast, best LOE)',
  retinexFallback: 'Retinex+ZeroDCE+SNR (no ANE, optimized fallback)',
  hviFallback: 'HVI-CIDNet fallback (color-best, experimental)',
};

export function LowLightPanel({ onClose }: { onClose: ()=>void }) {
  const [target, setTarget] = useState<Target>('balanced');
  const [strategy, setStrategy] = useState<Strategy>('auto');
  const [info, setInfo] = useState<any>(null);

  useEffect(()=>{ Pro.getLowLightMetrics().then(setInfo).catch(()=>{}); },[]);
  const apply = (t: Target, s: Strategy) => {
    setTarget(t); setStrategy(s);
    Pro.setLowLightStrategy(s as any, t as any);
  };

  return (
    <View style={s.sheet}>
      <View style={s.head}><Text style={s.title}>Night Boost — Metrics Optimized</Text><Pressable onPress={onClose}><Text style={s.close}>✕</Text></Pressable></View>
      <Text style={s.hint}>Tuned against awesome-low-light#metrics. Fallback Retinex uses Zero-DCE curves (LOE-safe) + SNR-Aware fusion (PSNR) + NIQE guard. ANE uses Retinexformer/HVI when .mlmodelc present.</Text>
      <Text style={s.label}>Target metric</Text>
      <View style={s.rowWrap}>
        {(Object.keys(TARGET_DESC) as Target[]).map(k=>(
          <Pressable key={k} onPress={()=> apply(k, strategy)} style={[s.chip, target===k && s.chipOn]}><Text style={[s.txt, target===k && s.txtOn]}>{k.toUpperCase()}</Text></Pressable>
        ))}
      </View>
      <Text style={s.desc}>{TARGET_DESC[target]}</Text>

      <Text style={s.label}>Strategy</Text>
      {(Object.keys(STRATEGY_DESC) as Strategy[]).map(k=>(
        <Pressable key={k} onPress={()=> apply(target, k)} style={[s.strRow, strategy===k && s.strOn]}>
          <Text style={[s.strTxt, strategy===k && s.strTxtOn]}>{k}</Text>
          <Text style={s.strDesc}>{STRATEGY_DESC[k]}</Text>
        </Pressable>
      ))}

      <View style={s.infoBox}>
        <Text style={s.infoTxt}>Current: {info ? `${info.strategy} / ${info.target} ${info.isANE ? '(ANE)' : '(fallback)'}` : 'auto/balanced'}</Text>
        <Text style={s.infoTxt}>Evaluate: python scripts/evaluate_lowlight.py --output out --reference gt --paired</Text>
        <Text style={s.infoTxt}>Metrics: PSNR↑ SSIM↑ LPIPS↓ LOE↓ NIQE↓ (see LowLightMetrics.swift)</Text>
        <Text style={s.infoTxt}>Tips: PSNR→ small blur 8, α×0.9, sharp 0.4. Natural→ α×0.78, larger blur 10, less vibrance. See LowLightEnhancer.swift:targetMetric.</Text>
      </View>
    </View>
  );
}
const s = StyleSheet.create({
  sheet:{position:'absolute', bottom:0, left:0, right:0, backgroundColor:'#0f0f0f', padding:12, borderTopLeftRadius:16, borderTopRightRadius:16, borderWidth:1, borderColor:'#333', gap:6, maxHeight:'78%'},
  head:{flexDirection:'row', justifyContent:'space-between', alignItems:'center'},
  title:{color:'#fff', fontWeight:'800', fontSize:13},
  close:{color:'#fff', fontSize:18, padding:6},
  hint:{color:'#888', fontSize:10},
  label:{color:'#ccc', fontSize:11, fontWeight:'700', marginTop:6},
  desc:{color:'#666', fontSize:10},
  rowWrap:{flexDirection:'row', gap:6, flexWrap:'wrap'},
  chip:{backgroundColor:'#1a1a1a', paddingHorizontal:10, paddingVertical:6, borderRadius:20, borderWidth:1, borderColor:'#333'},
  chipOn:{backgroundColor:'#f5c518', borderColor:'#f5c518'},
  txt:{color:'#aaa', fontSize:11, fontWeight:'700'},
  txtOn:{color:'#000'},
  strRow:{backgroundColor:'#1a1a1a', padding:8, borderRadius:10, borderWidth:1, borderColor:'#222', marginTop:4},
  strOn:{backgroundColor:'#222', borderColor:'#f5c518'},
  strTxt:{color:'#fff', fontWeight:'700', fontSize:11},
  strTxtOn:{color:'#f5c518'},
  strDesc:{color:'#888', fontSize:10, marginTop:2},
  infoBox:{backgroundColor:'#111', padding:8, borderRadius:10, borderWidth:1, borderColor:'#222', marginTop:6, gap:2},
  infoTxt:{color:'#666', fontSize:9},
});
