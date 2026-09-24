import React, { useState, useEffect } from 'react';
import { View, StatusBar } from 'react-native';
import { FeatureChooser, defaultFlags, FeatureFlags } from './components/FeatureChooser';
import { CameraScreen } from './components/CameraScreen';
import { AnalyticsPanel } from './components/AnalyticsPanel';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Logger, installGlobalLogger } from './utils/Logger';

const KEY = '@pro_camera_flags';
const HAS_SEEN = '@pro_camera_seen';

export default function App(){
  const [flags, setFlags] = useState<FeatureFlags>(defaultFlags);
  const [showChooser, setShowChooser] = useState(true);
  const [showAnalytics, setShowAnalytics] = useState(false);
  const [ready, setReady] = useState(false);

  useEffect(()=>{ installGlobalLogger(); Logger.info('App start', 'JS', { flags: defaultFlags }); },[]);
  useEffect(()=>{(async()=>{
    try{
      const raw = await AsyncStorage.getItem(KEY);
      const seen = await AsyncStorage.getItem(HAS_SEEN);
      if(raw){ const parsed = JSON.parse(raw); setFlags({...defaultFlags, ...parsed}); }
      if(seen) setShowChooser(false);
      Logger.info('App flags loaded', 'JS', { raw: !!raw, seen: !!seen });
    }catch(e:any){ Logger.error('App load failed', 'JS', { err: String(e?.message||e) }); } finally{ setReady(true); }
  })()},[]);

  const saveAndStart = async (f: FeatureFlags = flags)=>{
    setFlags(f);
    await AsyncStorage.setItem(KEY, JSON.stringify(f));
    await AsyncStorage.setItem(HAS_SEEN, '1');
    setShowChooser(false);
  };

  if(!ready) return <View style={{flex:1, backgroundColor:'#000'}} />;
  return (
    <View style={{flex:1, backgroundColor:'#000'}}>
      <StatusBar barStyle="light-content" />
      {showAnalytics
        ? <AnalyticsPanel onClose={()=> setShowAnalytics(false)} />
        : showChooser
          ? <FeatureChooser value={flags} onChange={setFlags} onDone={()=> saveAndStart()} onOpenAnalytics={()=> setShowAnalytics(true)} />
          : <CameraScreen flags={flags} onOpenChooser={()=> setShowChooser(true)} />}
    </View>
  );
}
