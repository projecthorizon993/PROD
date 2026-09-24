import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet, Pressable, TextInput, Alert, ScrollView } from 'react-native';
import * as Pro from '../native/ProCamera';
import RNFS from 'react-native-fs';
import AsyncStorage from '@react-native-async-storage/async-storage';

let RNSlider: any = null; try { RNSlider = require('@react-native-community/slider').default } catch {}

export function ColorGradingPanel({ onClose }: { onClose: () => void }) {
  const [exp, setExp] = useState(0);
  const [contrast, setContrast] = useState(1);
  const [sat, setSat] = useState(1);
  const [temp, setTemp] = useState(0);
  const [tint, setTint] = useState(0);
  const [shadows, setShadows] = useState(0);
  const [highlights, setHighlights] = useState(0);
  const [vibrance, setVibrance] = useState(0);
  const [hue, setHue] = useState(0);
  const [lutIntensity, setLutIntensity] = useState(1);
  const [lutPath, setLutPath] = useState('');
  const [luts, setLuts] = useState<string[]>([]);
  const [currentLUT, setCurrentLUT] = useState<string | null>(null);
  // Lift/Gamma/Gain per channel
  const [lift, setLift] = useState<[number, number, number]>([0, 0, 0]);
  const [gamma, setGamma] = useState<[number, number, number]>([1, 1, 1]);
  const [gain, setGain] = useState<[number, number, number]>([1, 1, 1]);
  const [showAdvanced, setShowAdvanced] = useState(false);

  const push = (p: any) => Pro.isAvailable && Pro.setGrading(p);
  const refreshLUTs = async () => {
    try {
      const list = await Pro.listLUTs();
      setLuts(list);
      const info = await Pro.getLUTInfo();
      setCurrentLUT(info.name);
      setLutIntensity(info.intensity);
    } catch {}
    // also list Documents via RNFS for UX
    try {
      const files = await RNFS.readDir(RNFS.DocumentDirectoryPath);
      const cubes = files.filter(f => f.name.toLowerCase().endsWith('.cube')).map(f => f.name);
      setLuts(prev => Array.from(new Set([...prev, ...cubes])).sort());
    } catch {}
  };
  useEffect(() => { refreshLUTs(); }, []);

  const Row = ({ label, value, min, max, onChange }: { label: string; value: number; min: number; max: number; onChange: (v: number) => void }) => (
    <View style={{ gap: 2 }}>
      <Text style={s.label}>{label} {value.toFixed(2)}</Text>
      {RNSlider ? <RNSlider value={value} minimumValue={min} maximumValue={max} onValueChange={onChange} minimumTrackTintColor="#f5c518" />
        : <View style={{ flexDirection: 'row', gap: 6 }}><Pressable onPress={() => onChange(Math.max(min, value - (max - min) / 10))} style={s.step}><Text>-</Text></Pressable><View style={{ flex: 1, height: 6, backgroundColor: '#333', borderRadius: 3, marginTop: 12 }}><View style={{ width: `${((value - min) / (max - min)) * 100}%`, height: 6, backgroundColor: '#f5c518', borderRadius: 3 }} /></View><Pressable onPress={() => onChange(Math.min(max, value + (max - min) / 10))} style={s.step}><Text>+</Text></Pressable></View>}
    </View>
  );

  const applyLift = (c: 0 | 1 | 2, v: number) => { const n = [...lift] as [number, number, number]; n[c] = v; setLift(n); push({ lift: n }); };
  const applyGamma = (c: 0 | 1 | 2, v: number) => { const n = [...gamma] as [number, number, number]; n[c] = v; setGamma(n); push({ gamma: n }); };
  const applyGain = (c: 0 | 1 | 2, v: number) => { const n = [...gain] as [number, number, number]; n[c] = v; setGain(n); push({ gain: n }); };

  return (
    <View style={s.sheet}>
      <View style={s.head}><Text style={s.title}>Live Color Grading + LUT custom</Text><Pressable onPress={onClose}><Text style={s.close}>✕</Text></Pressable></View>
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ gap: 6, paddingBottom: 12 }}>
        <Row label="Exposure EV" value={exp} min={-2} max={2} onChange={v => { setExp(v); push({ exposure: v }); }} />
        <Row label="Contrast" value={contrast} min={0.5} max={1.8} onChange={v => { setContrast(v); push({ contrast: v }); }} />
        <Row label="Saturation" value={sat} min={0} max={2} onChange={v => { setSat(v); push({ saturation: v }); }} />
        <Row label="Temperature" value={temp} min={-1} max={1} onChange={v => { setTemp(v); push({ temperature: v }); }} />
        <Row label="Tint" value={tint} min={-1} max={1} onChange={v => { setTint(v); push({ tint: v }); }} />
        <Row label="Shadows" value={shadows} min={-1} max={1} onChange={v => { setShadows(v); push({ shadows: v }); }} />
        <Row label="Highlights" value={highlights} min={-1} max={1} onChange={v => { setHighlights(v); push({ highlights: v }); }} />
        <Row label="Vibrance" value={vibrance} min={-1} max={1} onChange={v => { setVibrance(v); push({ vibrance: v }); }} />
        <Row label="Hue shift" value={hue} min={-0.5} max={0.5} onChange={v => { setHue(v); push({ hue: v }); }} />

        <Pressable onPress={() => setShowAdvanced(v => !v)} style={s.advBtn}><Text style={s.advTxt}>{showAdvanced ? 'Hide Lift/Gamma/Gain' : 'Show Lift / Gamma / Gain (per channel)'}</Text></Pressable>
        {showAdvanced && (
          <View style={{ gap: 8, backgroundColor: '#0f0f0f', padding: 8, borderRadius: 10, borderWidth: 1, borderColor: '#222' }}>
            <Text style={s.subTitle}>Lift (shadows offset) -0.3..0.3</Text>
            {(['R', 'G', 'B'] as const).map((ch, i) => (
              <Row key={`lift-${ch}`} label={`Lift ${ch}`} value={lift[i]} min={-0.3} max={0.3} onChange={v => applyLift(i as 0 | 1 | 2, v)} />
            ))}
            <Text style={s.subTitle}>Gamma (mid power) 0.5..2.0</Text>
            {(['R', 'G', 'B'] as const).map((ch, i) => (
              <Row key={`gamma-${ch}`} label={`Gamma ${ch}`} value={gamma[i]} min={0.5} max={2} onChange={v => applyGamma(i as 0 | 1 | 2, v)} />
            ))}
            <Text style={s.subTitle}>Gain (highlights) 0..2.0</Text>
            {(['R', 'G', 'B'] as const).map((ch, i) => (
              <Row key={`gain-${ch}`} label={`Gain ${ch}`} value={gain[i]} min={0} max={2} onChange={v => applyGain(i as 0 | 1 | 2, v)} />
            ))}
          </View>
        )}

        {/* LUT */}
        <View style={{ backgroundColor: '#0f0f0f', padding: 8, borderRadius: 10, borderWidth: 1, borderColor: '#222', gap: 6 }}>
          <Text style={s.subTitle}>LUT file support (.cube 17/32/33/64, ANE via CIColorCube)</Text>
          <Text style={s.hint}>Current: {currentLUT ?? '(none)'} {currentLUT ? `· intensity ${(lutIntensity * 100).toFixed(0)}%` : ''}</Text>
          <Row label="LUT intensity" value={lutIntensity} min={0} max={1} onChange={v => { setLutIntensity(v); Pro.setLUTIntensity(v); }} />
          <View style={s.lutRow}>
            <TextInput value={lutPath} onChangeText={setLutPath} placeholder="filename.cube or /Documents/…" placeholderTextColor="#666" style={s.input} />
            <Pressable style={s.btn} onPress={async () => {
              if (!lutPath) { Alert.alert('LUT', 'Enter filename or full path. LUTs in Documents are listed below.'); return; }
              const res: any = await Pro.loadLUT(lutPath);
              Alert.alert('LUT', res.loaded ? `Loaded ✓ ${res.name ?? lutPath} (size decoded, CIColorCube ready)` : 'Failed — check Documents/bundle, expects LUT_3D_SIZE header');
              refreshLUTs();
            }}><Text style={s.btnText}>Load</Text></Pressable>
          </View>
          <View style={{ flexDirection: 'row', gap: 6, flexWrap: 'wrap' }}>
            {luts.length === 0 ? <Text style={s.hint}>(no .cube found — drop via Files app, AirDrop, or bundle in Xcode)</Text> : luts.map(n => (
              <Pressable key={n} onPress={async () => { await Pro.loadLUT(n); setCurrentLUT(n); Alert.alert('LUT', `Loaded ${n}`); }} style={[s.chip, currentLUT === n && s.chipOn]}><Text style={[s.chipTxt, currentLUT === n && s.chipTxtOn]}>{n}</Text></Pressable>
            ))}
          </View>
          <View style={{ flexDirection: 'row', gap: 6 }}>
            <Pressable style={[s.btn, { flex: 1 }]} onPress={async () => { await Pro.clearLUT(); setCurrentLUT(null); Alert.alert('LUT', 'Cleared'); }}><Text style={s.btnText}>Clear LUT</Text></Pressable>
            <Pressable style={[s.btn, { flex: 1, backgroundColor: '#222', borderWidth: 1, borderColor: '#333' }]} onPress={async () => {
              try { const files = await RNFS.readDir(RNFS.DocumentDirectoryPath); Alert.alert('Documents', files.filter(f => f.name.endsWith('.cube')).map(f => f.name).join('\n') || '(no .cube)'); } catch (e: any) { Alert.alert('Error', String(e)); }
            }}><Text style={[s.btnText, { color: '#fff' }]}>List Docs</Text></Pressable>
          </View>
          <View style={{ flexDirection: 'row', gap: 6 }}>
            <Pressable style={[s.btn, { flex: 1, backgroundColor: '#f5c518' }]} onPress={async () => {
              const name = `ProCamera_${Date.now()}.cube`;
              const res: any = await Pro.bakeLUT(name, 33);
              Alert.alert('Bake LUT', res.saved ? `Saved → Documents/${name}\n${res.url}` : 'Failed');
              refreshLUTs();
            }}><Text style={s.btnText}>Bake current grading → .cube (33)</Text></Pressable>
          </View>
          <Text style={s.hint}>Import other project’s .cube (DaVinci/Photoshop/LUTCalc) via Files → On My iPhone → ProCamera. Intensity blends via Metal mixKernel for true 0-100%.</Text>
        </View>

        {/* Preset */}
        <View style={{ flexDirection: 'row', gap: 6 }}>
          <Pressable style={[s.btn, { flex: 1 }]} onPress={async () => {
            const { json } = await Pro.exportPreset();
            await AsyncStorage.setItem('@grading_preset', json);
            Alert.alert('Preset', 'Saved to AsyncStorage @grading_preset');
          }}><Text style={s.btnText}>Save preset</Text></Pressable>
          <Pressable style={[s.btn, { flex: 1, backgroundColor: '#222', borderWidth: 1, borderColor: '#333' }]} onPress={async () => {
            const json = await AsyncStorage.getItem('@grading_preset');
            if (!json) { Alert.alert('Preset', 'No saved preset'); return; }
            const res: any = await Pro.importPreset(json);
            Alert.alert('Preset', res.imported ? 'Loaded' : 'Failed');
            if (res.imported) {
              try { const p = JSON.parse(json); setExp(p.params.exposure ?? 0); setContrast(p.params.contrast ?? 1); setSat(p.params.saturation ?? 1); setTemp(p.params.temperature ?? 0); setTint(p.params.tint ?? 0); setShadows(p.params.shadows ?? 0); setHighlights(p.params.highlights ?? 0); setVibrance(p.params.vibrance ?? 0); setHue(p.params.hue ?? 0); setLutIntensity(p.params.lutIntensity ?? 1); if (p.params.lift) setLift(p.params.lift); if (p.params.gamma) setGamma(p.params.gamma); if (p.params.gain) setGain(p.params.gain); } catch {}
            }
          }}><Text style={[s.btnText, { color: '#fff' }]}>Load preset</Text></Pressable>
        </View>
        <Pressable style={[s.btn, { backgroundColor: '#222', borderWidth: 1, borderColor: '#333' }]} onPress={() => { setExp(0); setContrast(1); setSat(1); setTemp(0); setTint(0); setShadows(0); setHighlights(0); setVibrance(0); setHue(0); setLutIntensity(1); setLift([0, 0, 0]); setGamma([1, 1, 1]); setGain([1, 1, 1]); push({ exposure: 0, contrast: 1, saturation: 1, temperature: 0, tint: 0, shadows: 0, highlights: 0, vibrance: 0, hue: 0, lutIntensity: 1, lift: [0, 0, 0], gamma: [1, 1, 1], gain: [1, 1, 1] }); }}><Text style={[s.btnText, { color: '#fff' }]}>Reset grading</Text></Pressable>
        <Text style={s.hint}>ColorGradingEngine fuses lift/gamma/gain in one Metal kernel + CIColorCube (LUT) at 60 fps. Bake exports true .cube (33) via GPU so your custom look is portable to other project.</Text>
      </ScrollView>
    </View>
  );
}
const s = StyleSheet.create({
  sheet: { position: 'absolute', bottom: 0, left: 0, right: 0, backgroundColor: '#111', padding: 12, borderTopLeftRadius: 16, borderTopRightRadius: 16, borderWidth: 1, borderColor: '#333', maxHeight: '88%' },
  head: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  title: { color: '#fff', fontWeight: '800', fontSize: 13 },
  close: { color: '#fff', fontSize: 18, padding: 6 },
  label: { color: '#ccc', fontSize: 11 },
  subTitle: { color: '#f5c518', fontSize: 11, fontWeight: '700' },
  input: { flex: 1, backgroundColor: '#1a1a1a', color: '#fff', paddingHorizontal: 8, paddingVertical: 6, borderRadius: 8, borderWidth: 1, borderColor: '#333', fontSize: 11 },
  lutRow: { flexDirection: 'row', gap: 6, marginTop: 2 },
  btn: { backgroundColor: '#f5c518', paddingHorizontal: 10, paddingVertical: 8, borderRadius: 10, alignItems: 'center' },
  btnText: { color: '#000', fontWeight: '700', fontSize: 11 },
  hint: { color: '#666', fontSize: 9, marginTop: 2 },
  step: { width: 32, height: 32, borderRadius: 16, backgroundColor: '#222', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#333' },
  chip: { backgroundColor: '#1a1a1a', paddingHorizontal: 10, paddingVertical: 6, borderRadius: 16, borderWidth: 1, borderColor: '#333' },
  chipOn: { backgroundColor: '#f5c518', borderColor: '#f5c518' },
  chipTxt: { color: '#aaa', fontSize: 11, fontWeight: '700' },
  chipTxtOn: { color: '#000' },
  advBtn: { backgroundColor: '#0f0f0f', padding: 8, borderRadius: 10, borderWidth: 1, borderColor: '#222', alignItems: 'center' },
  advTxt: { color: '#f5c518', fontSize: 11, fontWeight: '700' },
});
