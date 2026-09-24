import React, { useEffect, useState } from 'react';
import { Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import * as Pro from '../native/ProCamera';
import { Logger } from '../utils/Logger';
import { LogViewer } from './LogViewer';

type Metrics = {
  strategy: string;
  target: string;
  isANE: boolean;
  zoom: number;
  lens: string;
  seamless: boolean;
};

export function AnalyticsPanel({ onClose }: { onClose: () => void }) {
  const [metrics, setMetrics] = useState<Metrics | null>(null);
  const [logPreview, setLogPreview] = useState('Loading logs…');
  const [captureCount, setCaptureCount] = useState(0);
  const [showLogs, setShowLogs] = useState(false);

  const load = async () => {
    try {
      const [lowLight, zoom] = await Promise.all([Pro.getLowLightMetrics(), Pro.getZoomInfo()]);
      setMetrics({
        strategy: lowLight.strategy,
        target: lowLight.target,
        isANE: lowLight.isANE,
        zoom: zoom.zoom,
        lens: zoom.activeLens,
        seamless: zoom.seamless,
      });
    } catch {}
    try {
      const recent = Logger.getRing();
      const native = await Pro.getLogs();
      const recentText = recent.slice(-30).join('\n');
      const nativeText = native.slice(-1500);
      setLogPreview([recentText, nativeText].filter(Boolean).join('\n\n=== Native ===\n') || 'No logs yet');
      setCaptureCount(recent.filter(line => /capture|photo|recording/i.test(line)).length);
    } catch {
      const recent = Logger.getRing();
      setLogPreview(recent.slice(-30).join('\n') || 'No logs yet');
      setCaptureCount(recent.filter(line => /capture|photo|recording/i.test(line)).length);
    }
  };

  useEffect(() => {
    void load();
    const id = setInterval(() => void load(), 4000);
    return () => clearInterval(id);
  }, []);

  const clear = async () => {
    await Logger.clear();
    setCaptureCount(0);
    setLogPreview('Logs cleared');
  };

  if (showLogs) return <LogViewer onClose={() => setShowLogs(false)} />;

  return (
    <View style={s.wrap}>
      <View style={s.header}>
        <Text style={s.title}>Analytics & Logs</Text>
        <Pressable onPress={onClose} style={s.close}><Text style={s.closeText}>Close</Text></Pressable>
      </View>
      <ScrollView contentContainerStyle={s.content}>
        <View style={s.card}>
          <Text style={s.cardTitle}>Device & Session</Text>
          <Text style={s.row}>Platform: {Platform.OS} {String(Platform.Version)}</Text>
          <Text style={s.row}>Native camera: {Pro.isAvailable ? 'available' : 'fallback'}</Text>
          <Text style={s.row}>Captures in recent log: {captureCount}</Text>
          <Text style={s.row}>Recent log entries: {Logger.getRing().length}</Text>
        </View>
        <View style={s.card}>
          <Text style={s.cardTitle}>Live Metrics</Text>
          {metrics ? (
            <>
              <Text style={s.row}>Low light: {metrics.strategy} / {metrics.target}</Text>
              <Text style={s.row}>ANE: {metrics.isANE ? 'active' : 'fallback'}</Text>
              <Text style={s.row}>Zoom: {metrics.zoom.toFixed(2)}×</Text>
              <Text style={s.row}>Lens: {metrics.lens}</Text>
              <Text style={s.row}>Seamless zoom: {metrics.seamless ? 'enabled' : 'disabled'}</Text>
            </>
          ) : <Text style={s.row}>Waiting for native metrics…</Text>}
          <Pressable onPress={() => void load()} style={s.secondary}><Text style={s.actionText}>Refresh</Text></Pressable>
        </View>
        <View style={s.card}>
          <Text style={s.cardTitle}>Recent Device Logs</Text>
          <Text style={s.hint}>The preview refreshes automatically every four seconds.</Text>
          <View style={s.logBox}><Text selectable style={s.mono}>{logPreview}</Text></View>
          <View style={s.actions}>
            <Pressable onPress={() => setShowLogs(true)} style={s.primary}><Text style={s.actionText}>Open full logs</Text></Pressable>
            <Pressable onPress={() => void clear()} style={s.danger}><Text style={s.actionText}>Clear logs</Text></Pressable>
          </View>
        </View>
        <View style={s.card}>
          <Text style={s.cardTitle}>Console Access</Text>
          <Text style={s.row}>Use Xcode device logs or Console.app and filter by subsystem com.camerapp.</Text>
          <Text style={s.row}>From macOS, run log stream with the predicate subsystem == "com.camerapp".</Text>
        </View>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: '#0a0a0a' },
  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingTop: 48, paddingBottom: 12 },
  title: { flex: 1, color: '#fff', fontWeight: '800', fontSize: 18 },
  close: { paddingHorizontal: 12, paddingVertical: 8, backgroundColor: '#222', borderRadius: 10 },
  closeText: { color: '#fff', fontWeight: '700' },
  content: { padding: 16, paddingBottom: 40 },
  card: { backgroundColor: '#151515', borderRadius: 14, padding: 14, marginBottom: 12, borderWidth: 1, borderColor: '#222' },
  cardTitle: { color: '#fff', fontWeight: '800', marginBottom: 8 },
  row: { color: '#ccc', fontSize: 12, marginBottom: 4 },
  hint: { color: '#777', fontSize: 11, marginBottom: 8 },
  logBox: { backgroundColor: '#0f0f0f', borderRadius: 10, padding: 10, maxHeight: 190, borderWidth: 1, borderColor: '#222' },
  mono: { color: '#8ef', fontSize: 10, fontFamily: 'Menlo', lineHeight: 13 },
  actions: { flexDirection: 'row', gap: 8, marginTop: 10, flexWrap: 'wrap' },
  primary: { backgroundColor: '#fff', paddingHorizontal: 14, paddingVertical: 8, borderRadius: 12 },
  secondary: { alignSelf: 'flex-start', backgroundColor: '#222', paddingHorizontal: 14, paddingVertical: 8, borderRadius: 12, marginTop: 8 },
  danger: { backgroundColor: '#5a1e1e', paddingHorizontal: 14, paddingVertical: 8, borderRadius: 12 },
  actionText: { color: '#fff', fontWeight: '700', fontSize: 12 },
});
