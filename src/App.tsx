import React, { useState, useEffect } from 'react';
import { View, StatusBar } from 'react-native';
import { FeatureChooser, defaultFlags, FeatureFlags } from './components/FeatureChooser';
import { CameraScreen } from './components/CameraScreen';
import AsyncStorage from '@react-native-async-storage/async-storage';

const KEY = '@pro_camera_flags';
const HAS_SEEN = '@pro_camera_seen';

export default function App(){
  const [flags, setFlags] = useState<FeatureFlags>(defaultFlags);
  const [showChooser, setShowChooser] = useState(true);
  const [ready, setReady] = useState(false);

  useEffect(()=>{(async()=>{
    try{
      const raw = await AsyncStorage.getItem(KEY);
      const seen = await AsyncStorage.getItem(HAS_SEEN);
      if(raw){ const parsed = JSON.parse(raw); setFlags({...defaultFlags, ...parsed}); }
      if(seen) setShowChooser(false);
    }catch{} finally{ setReady(true); }
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
      {showChooser ? <FeatureChooser value={flags} onChange={setFlags} onDone={()=> saveAndStart()} /> : <CameraScreen flags={flags} onOpenChooser={()=> setShowChooser(true)} />}
    </View>
  );
}
