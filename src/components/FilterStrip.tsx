import React from 'react';
import { ScrollView, Pressable, Text, StyleSheet } from 'react-native';
import * as Pro from '../native/ProCamera';

export function FilterStrip({value, onChange}:{value:string; onChange:(v:string)=>void}){
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.row}>
      {Pro.Filters.map(f=>(
        <Pressable key={f} onPress={()=> onChange(f)} style={[s.chip, value===f && s.chipOn]}>
          <Text style={[s.txt, value===f && s.txtOn]}>{f}</Text>
        </Pressable>
      ))}
    </ScrollView>
  );
}
const s=StyleSheet.create({
  row:{gap:8, paddingHorizontal:8},
  chip:{backgroundColor:'rgba(0,0,0,0.6)', paddingHorizontal:12, paddingVertical:8, borderRadius:20, borderWidth:1, borderColor:'#333'},
  chipOn:{backgroundColor:'#fff', borderColor:'#fff'},
  txt:{color:'#fff', fontSize:12, fontWeight:'600'},
  txtOn:{color:'#000'},
});
