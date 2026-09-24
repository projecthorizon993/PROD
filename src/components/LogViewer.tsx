import React, { useEffect, useState } from 'react';
import { NativeModules, Share, StyleSheet, Text, View, Pressable, ScrollView, Alert } from 'react-native';
import { Logger } from '../utils/Logger';

export function LogViewer({ onClose }: { onClose: () => void }) {
  const [text, setText] = useState('');
  const [source, setSource] = useState<'ring' | 'file'>('ring');

  const load = async (selected: 'ring' | 'file' = source) => {
    if (selected === 'ring') {
      setText(Logger.getRing().join('\n') || '(No logs yet)');
      return;
    }
    try {
      const module: any = NativeModules.ProCameraModule;
      const native = module?.getLogs ? await module.getLogs() : '';
      const exported = Logger.getRing().join('\n');
      setText(`=== Native ===\n${native || '(empty)'}\n\n=== JS ===\n${exported || '(empty)'}`);
    } catch (error: any) {
      setText(String(error?.message || error));
    }
  };

  useEffect(() => {
    void load(source);
    const id = setInterval(() => void load(source), 1500);
    return () => clearInterval(id);
  }, [source]);

  const share = async () => {
    try {
      const path = await Logger.export();
      await Share.share({ url: `file://${path}` });
    } catch (error: any) {
      Alert.alert('Export failed', String(error?.message || error));
    }
  };

  const clear = async () => {
    await Logger.clear();
    setText('(Logs cleared)');
  };

  return (
    <View style={s.wrap}>
      <View style={s.header}>
        <Text style={s.title}>Device Logs</Text>
        <Pressable onPress={onClose} style={s.close}><Text style={s.closeText}>Close</Text></Pressable>
      </View>
      <Text style={s.hint}>Real-device OS logs and persistent app logs. The native subsystem is com.camerapp.</Text>
      <View style={s.actions}>
        <Pressable onPress={() => setSource('ring')} style={[s.action, source === 'ring' && s.actionOn]}><Text style={s.actionText}>Recent</Text></Pressable>
        <Pressable onPress={() => setSource('file')} style={[s.action, source === 'file' && s.actionOn]}><Text style={s.actionText}>Full file</Text></Pressable>
        <Pressable onPress={share} style={s.share}><Text style={s.actionText}>Share</Text></Pressable>
        <Pressable onPress={clear} style={s.clear}><Text style={s.actionText}>Clear</Text></Pressable>
      </View>
      <ScrollView style={s.scroll} contentContainerStyle={s.content}>
        <Text selectable style={s.mono}>{text}</Text>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: '#0a0a0a', paddingTop: 48 },
  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, marginBottom: 6 },
  title: { flex: 1, color: '#fff', fontWeight: '800', fontSize: 17 },
  close: { paddingHorizontal: 12, paddingVertical: 8, backgroundColor: '#222', borderRadius: 10 },
  closeText: { color: '#fff', fontWeight: '700' },
  hint: { color: '#888', fontSize: 11, paddingHorizontal: 16, marginBottom: 10 },
  actions: { flexDirection: 'row', gap: 8, paddingHorizontal: 16, marginBottom: 8, flexWrap: 'wrap' },
  action: { paddingHorizontal: 12, paddingVertical: 8, borderRadius: 12, backgroundColor: '#1a1a1a', borderWidth: 1, borderColor: '#333' },
  actionOn: { backgroundColor: '#fff', borderColor: '#fff' },
  share: { paddingHorizontal: 12, paddingVertical: 8, borderRadius: 12, backgroundColor: '#1e3a5f' },
  clear: { paddingHorizontal: 12, paddingVertical: 8, borderRadius: 12, backgroundColor: '#5a1e1e' },
  actionText: { color: '#fff', fontWeight: '700', fontSize: 12 },
  scroll: { flex: 1, backgroundColor: '#111', marginHorizontal: 12, marginBottom: 12, borderRadius: 12, borderWidth: 1, borderColor: '#222' },
  content: { padding: 12 },
  mono: { color: '#9ef', fontFamily: 'Menlo', fontSize: 10, lineHeight: 14 },
});
