import React from 'react';
import { View, Image, Text, StyleSheet, Pressable, Linking, Alert } from 'react-native';
import RNFS from 'react-native-fs';

export function GalleryPreview({uri}:{uri:string|null}){
  if(!uri) return <View style={s.empty}><Text style={s.emptyTxt}>No capture yet — photo/video appears here. ANE-enhanced stills are saved to Photo Library.</Text></View>;
  const isVideo = uri.endsWith('.mov') || uri.endsWith('.mp4');
  return (
    <View style={s.wrap}>
      {isVideo ? <View style={s.videoBadge}><Text style={s.videoTxt}>▶ VIDEO {uri.split('/').pop()}</Text></View> : <Image source={{uri}} style={s.thumb} />}
      <View style={{flex:1}}>
        <Text numberOfLines={1} style={s.uri}>{uri}</Text>
        <View style={{flexDirection:'row', gap:6, marginTop:4}}>
          <Pressable onPress={()=> Linking.openURL(uri)} style={s.btn}><Text style={s.btnTxt}>Open</Text></Pressable>
          <Pressable onPress={async()=>{
            try{ const exists = await RNFS.exists(uri.replace('file://','')); Alert.alert('File', exists? 'Exists ✓':'Not found'); }catch(e:any){ Alert.alert('Error', String(e))}
          }} style={[s.btn,{backgroundColor:'#222'}]}><Text style={[s.btnTxt,{color:'#fff'}]}>Check</Text></Pressable>
        </View>
      </View>
    </View>
  );
}
const s=StyleSheet.create({
  wrap:{flexDirection:'row', gap:8, backgroundColor:'#1a1a1a', padding:8, borderRadius:12, borderWidth:1, borderColor:'#333', alignItems:'center'},
  thumb:{width:64, height:64, borderRadius:8, backgroundColor:'#000'},
  videoBadge:{width:64, height:64, borderRadius:8, backgroundColor:'#222', alignItems:'center', justifyContent:'center', borderWidth:1, borderColor:'#333'},
  videoTxt:{color:'#fff', fontSize:9, fontWeight:'700', textAlign:'center'},
  uri:{color:'#aaa', fontSize:10},
  btn:{backgroundColor:'#fff', paddingHorizontal:10, paddingVertical:6, borderRadius:8},
  btnTxt:{color:'#000', fontWeight:'700', fontSize:11},
  empty:{backgroundColor:'#111', padding:8, borderRadius:10, borderWidth:1, borderColor:'#222'},
  emptyTxt:{color:'#666', fontSize:10},
});
