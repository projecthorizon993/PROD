import React, { useEffect, useRef, useState } from 'react';
import { View, Text, StyleSheet, Pressable, Alert, ScrollView, Platform } from 'react-native';
import { Camera, CameraType } from 'react-native-camera-kit';
import { check, request, PERMISSIONS, RESULTS } from 'react-native-permissions';
import * as Pro from '../native/ProCamera';
import { FeatureFlags } from './FeatureChooser';
import { ManualControls } from './ManualControls';
import { ColorGradingPanel } from './ColorGradingPanel';
import { FilterStrip } from './FilterStrip';
import { GalleryPreview } from './GalleryPreview';
import { LowLightPanel } from './LowLightPanel';
import { ZoomBar } from './ZoomBar';
import { SharpnessPanel } from './SharpnessPanel';
import { BracketPanel } from './BracketPanel';

export function CameraScreen({ flags, onOpenChooser }: { flags: FeatureFlags; onOpenChooser: ()=>void }) {
  const ref = useRef<any>(null);
  const [hasPerm, setHasPerm] = useState(false);
  const [camType, setCamType] = useState<CameraType>(CameraType.Back);
  const [isRecording, setIsRecording] = useState(false);
  const [isPhotoMode, setIsPhotoMode] = useState(true);
  const [showManual, setShowManual] = useState(false);
  const [showGrading, setShowGrading] = useState(false);
  const [lowLight, setLowLight] = useState(flags.lowLightANE);
  const [filter, setFilter] = useState('None');
  const [lastUri, setLastUri] = useState<string | null>(null);
  const [zoom, setZoom] = useState(1);
  const [showLowLight, setShowLowLight] = useState(false);
  const [showZoom, setShowZoom] = useState(false);
  const [showSharp, setShowSharp] = useState(false);
  const [showBracket, setShowBracket] = useState(false);

  useEffect(()=>{ (async()=>{
    const perm = Platform.OS==='ios' ? PERMISSIONS.IOS.CAMERA : PERMISSIONS.ANDROID.CAMERA;
    let r = await check(perm);
    if(r!==RESULTS.GRANTED) r = await request(perm);
    setHasPerm(r===RESULTS.GRANTED);
    if(Pro.isAvailable) {
      Pro.setLowLightBoost(lowLight);
      Pro.setSharpness(0.55,'balanced');
    }
  })()},[]);

  useEffect(()=>{ if(Pro.isAvailable) Pro.setLowLightBoost(lowLight); },[lowLight]);
  useEffect(()=>{ if(Pro.isAvailable) Pro.setFilter(filter); },[filter]);
  useEffect(()=>{ if(Pro.isAvailable){ Pro.setZoom(zoom); } },[zoom]);

  const capture = async () => {
    try {
      if(Pro.isAvailable){
        const res = await Pro.capturePhoto({flash:'auto'});
        if(res.uri) setLastUri(res.uri);
        return;
      }
      // fallback to camera-kit
      const data = await ref.current?.capture?.(true);
      if(data?.uri) setLastUri(data.uri);
    } catch(e:any){ Alert.alert('Capture failed', String(e?.message??e)); }
  };

  const toggleRec = async () => {
    if(!flags.video) return;
    if(Pro.isAvailable){
      if(!isRecording){ await Pro.startRecording(); setIsRecording(true);} else { const r=await Pro.stopRecording(); setIsRecording(false); if(r.url) setLastUri(r.url); }
      return;
    }
    // camera-kit video not implemented - alert
    Alert.alert('Video', 'Wire ProCameraModule for 4K recording (ANE pipeline ready). Fallback needs native video encoder.');
  };

  const switchCam = async () => {
    if(!flags.cameraSwitch) return;
    if(Pro.isAvailable){ await Pro.switchCamera(); } else { setCamType(p=> p===CameraType.Back? CameraType.Front: CameraType.Back); }
  };

  if(!hasPerm) return <View style={s.center}><Text style={{color:'#fff'}}>Requesting camera permission…</Text></View>;

  return (
    <View style={s.wrap}>
      <Camera
        ref={ref}
        style={StyleSheet.absoluteFillObject}
        cameraType={camType}
        flashMode="auto"
        zoomMode="on"
        zoom={zoom}
        focusMode="on"
        torchMode="off"
        onZoom={e=> setZoom(e.nativeEvent.zoom)}
      />

      {/* Top bar */}
      <View style={s.top}>
        <Pressable onPress={onOpenChooser} style={s.pill}><Text style={s.pillText}>⚙ Features</Text></Pressable>
        {flags.cameraSwitch && <Pressable onPress={switchCam} style={s.iconBtn}><Text style={s.icon}>⇄</Text></Pressable>}
        {flags.lowLightANE && (
          <>
            <Pressable onPress={()=> setLowLight(v=>!v)} style={[s.pill, lowLight && s.pillOn]}><Text style={[s.pillText, lowLight && {color:'#000'}]}>{lowLight? 'Night ON':'Night OFF'}</Text></Pressable>
            <Pressable onPress={()=> setShowLowLight(v=>!v)} style={s.pill}><Text style={s.pillText}>Night ⚙</Text></Pressable>
          </>
        )}
        {flags.bracketing && <Pressable onPress={()=> setShowBracket(v=>!v)} style={[s.pill, showBracket && s.pillOn]}><Text style={[s.pillText, showBracket && {color:'#000'}]}>Bracket</Text></Pressable>}
        {flags.zoom && <Pressable onPress={()=> setShowZoom(v=>!v)} style={s.pill}><Text style={s.pillText}>Zoom {zoom.toFixed(1)}×</Text></Pressable>}
      </View>

      {/* Filter strip */}
      {flags.filters && !showGrading && !showManual && (
        <View style={s.filterWrap}><FilterStrip value={filter} onChange={setFilter} /></View>
      )}

      {/* Bottom controls */}
      <View style={s.bottom}>
        <View style={{flexDirection:'row', gap:6, flexWrap:'wrap'}}>
          {flags.colorGrading && <Pressable onPress={()=> setShowGrading(v=>!v)} style={s.smallBtn}><Text style={s.smallTxt}>{showGrading? 'Hide Grading':'Grading'}</Text></Pressable>}
          {flags.manual && <Pressable onPress={()=> setShowManual(v=>!v)} style={s.smallBtn}><Text style={s.smallTxt}>{showManual? 'Hide Manual':'Manual'}</Text></Pressable>}
          {flags.sharpness && <Pressable onPress={()=> setShowSharp(v=>!v)} style={s.smallBtn}><Text style={s.smallTxt}>{showSharp? 'Hide Sharp':'Sharpness'}</Text></Pressable>}
          {flags.zoom && <Pressable onPress={()=> setShowZoom(v=>!v)} style={s.smallBtn}><Text style={s.smallTxt}>{showZoom? 'Hide Zoom':'Zoom'}</Text></Pressable>}
          {flags.bracketing && <Pressable onPress={()=> setShowBracket(v=>!v)} style={s.smallBtn}><Text style={s.smallTxt}>{showBracket? 'Hide Bracket':'Bracket'}</Text></Pressable>}
        </View>

        <View style={s.shutterRow}>
          <Pressable onPress={()=> setIsPhotoMode(true)} style={[s.modeBtn, isPhotoMode && s.modeOn]}><Text style={s.modeTxt}>Photo</Text></Pressable>
          <Pressable
            onPress={isPhotoMode? capture: toggleRec}
            style={[s.shutter, isRecording && s.shutterRec]}>
            <View style={[s.shutterInner, !isPhotoMode && {borderRadius:4, width:28, height:28}, isRecording && {backgroundColor:'#f00'}]} />
          </Pressable>
          <Pressable onPress={()=> setIsPhotoMode(false)} style={[s.modeBtn, !isPhotoMode && s.modeOn]}><Text style={s.modeTxt}>Video</Text></Pressable>
        </View>

        {flags.gallery && <GalleryPreview uri={lastUri} />}

        {!isPhotoMode && flags.video && <Text style={s.recHint}>{isRecording? '● REC (4K ANE pipeline)':'Tap square to record'}</Text>}
        {!Pro.isAvailable && <Text style={s.fallback}>Running in fallback (camera-kit). Build native target for ANE + grading.</Text>}
      </View>

      {showManual && flags.manual && <ManualControls onClose={()=> setShowManual(false)} />}
      {showGrading && flags.colorGrading && <ColorGradingPanel onClose={()=> setShowGrading(false)} />}
      {showLowLight && flags.lowLightANE && <LowLightPanel onClose={()=> setShowLowLight(false)} />}
      {showSharp && flags.sharpness && <SharpnessPanel onClose={()=> setShowSharp(false)} zoom={zoom} />}
      {showBracket && flags.bracketing && <BracketPanel onClose={()=> setShowBracket(false)} />}
      {showZoom && flags.zoom && (
        <View style={{position:'absolute', bottom:220, left:12, right:12}}>
          <ZoomBar zoom={zoom} onZoom={setZoom} />
        </View>
      )}
      {/* Zoom slider hint */}
      <View style={s.zoomBadge}><Text style={s.zoomText}>{zoom.toFixed(1)}×</Text></View>
    </View>
  );
}

const s = StyleSheet.create({
  wrap:{flex:1, backgroundColor:'#000'},
  center:{flex:1, backgroundColor:'#000', alignItems:'center', justifyContent:'center'},
  top:{position:'absolute', top:48, left:12, right:12, flexDirection:'row', alignItems:'center', gap:8, zIndex:10},
  pill:{backgroundColor:'rgba(0,0,0,0.6)', paddingHorizontal:12, paddingVertical:8, borderRadius:20, borderWidth:1, borderColor:'#333'},
  pillOn:{backgroundColor:'#f5c518', borderColor:'#f5c518'},
  pillText:{color:'#fff', fontWeight:'700', fontSize:12},
  iconBtn:{backgroundColor:'rgba(0,0,0,0.6)', width:40, height:40, borderRadius:20, alignItems:'center', justifyContent:'center', borderWidth:1, borderColor:'#333'},
  icon:{color:'#fff', fontSize:18},
  filterWrap:{position:'absolute', bottom:180, left:0, right:0, zIndex:5},
  bottom:{position:'absolute', bottom:0, left:0, right:0, padding:12, paddingBottom:18, backgroundColor:'rgba(0,0,0,0.55)', gap:8},
  smallBtn:{alignSelf:'flex-start', backgroundColor:'#1a1a1a', paddingHorizontal:10, paddingVertical:6, borderRadius:12, borderWidth:1, borderColor:'#333'},
  smallTxt:{color:'#fff', fontSize:12, fontWeight:'600'},
  shutterRow:{flexDirection:'row', alignItems:'center', justifyContent:'space-between', marginTop:4},
  modeBtn:{paddingHorizontal:12, paddingVertical:8, borderRadius:12, backgroundColor:'#222', borderWidth:1, borderColor:'#333'},
  modeOn:{backgroundColor:'#fff', borderColor:'#fff'},
  modeTxt:{color:'#aaa', fontWeight:'700', fontSize:12},
  shutter:{width:72, height:72, borderRadius:36, backgroundColor:'#fff', alignItems:'center', justifyContent:'center', borderWidth:4, borderColor:'#fff', shadowColor:'#000', shadowOpacity:0.3, shadowRadius:6},
  shutterRec:{borderColor:'#f00'},
  shutterInner:{width:56, height:56, borderRadius:28, backgroundColor:'#fff', borderWidth:2, borderColor:'#000'},
  recHint:{color:'#f55', fontSize:11, textAlign:'center'},
  fallback:{color:'#fa0', fontSize:10, textAlign:'center'},
  zoomBadge:{position:'absolute', top:100, alignSelf:'center', backgroundColor:'rgba(0,0,0,0.6)', paddingHorizontal:10, paddingVertical:4, borderRadius:12, left:'50%', marginLeft:-24},
  zoomText:{color:'#fff', fontWeight:'700'},
});
