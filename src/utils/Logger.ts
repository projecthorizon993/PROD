import { NativeModules } from 'react-native';
import RNFS from 'react-native-fs';

type LogLevel = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR';
type LogCategory = 'ProCamera' | 'ANE' | 'LowLight' | 'Lens' | 'Grading' | 'Bracket' | 'Zoom' | 'JS' | 'Bridge';

const MAX_MEMORY = 500;
const ring: string[] = [];
let fileEnabled = true;
let globalLoggerInstalled = false;

function timestamp() {
  return new Date().toISOString();
}

function format(level: LogLevel, category: LogCategory, message: string, meta?: any) {
  const details = meta ? ` ${JSON.stringify(meta).slice(0, 800)}` : '';
  return `${timestamp()} [${level}][${category}] ${message}${details}`;
}

async function appendToFile(line: string) {
  if (!fileEnabled) return;
  try {
    const path = `${RNFS.DocumentDirectoryPath}/procamera_js.log`;
    const stat = await RNFS.stat(path).catch(() => null);
    if (stat && Number(stat.size) > 2 * 1024 * 1024) {
      const data = await RNFS.readFile(path, 'utf8');
      await RNFS.writeFile(path, data.slice(-1024 * 1024), 'utf8');
    }
    await RNFS.appendFile(path, `${line}\n`, 'utf8');
  } catch {}
}

function push(line: string) {
  ring.push(line);
  if (ring.length > MAX_MEMORY) ring.shift();
  try {
    const module: any = NativeModules.ProCameraModule;
    if (module?.logMessage) module.logMessage(line).catch(() => {});
  } catch {}
  void appendToFile(line);
  console.log(line);
}

export const Logger = {
  debug(message: string, category: LogCategory = 'JS', meta?: any) {
    push(format('DEBUG', category, message, meta));
  },
  info(message: string, category: LogCategory = 'JS', meta?: any) {
    push(format('INFO', category, message, meta));
  },
  warn(message: string, category: LogCategory = 'JS', meta?: any) {
    push(format('WARN', category, message, meta));
  },
  error(message: string, category: LogCategory = 'JS', meta?: any) {
    push(format('ERROR', category, message, meta));
  },
  getRing() {
    return [...ring];
  },
  async clear() {
    ring.length = 0;
    const path = `${RNFS.DocumentDirectoryPath}/procamera_js.log`;
    await RNFS.unlink(path).catch(() => {});
    try {
      const module: any = NativeModules.ProCameraModule;
      if (module?.clearLogs) await module.clearLogs();
    } catch {}
  },
  async export(): Promise<string> {
    const jsPath = `${RNFS.DocumentDirectoryPath}/procamera_js.log`;
    let output = `=== JS ring (${ring.length}) ===\n${ring.join('\n')}\n\n`;
    try {
      const module: any = NativeModules.ProCameraModule;
      if (module?.getLogs) {
        const native = await module.getLogs();
        output += `=== Native procamera.log ===\n${native}\n\n`;
      } else {
        const native = await RNFS.readFile(`${RNFS.DocumentDirectoryPath}/procamera.log`, 'utf8').catch(() => '');
        if (native) output += `=== Native procamera.log ===\n${native}\n\n`;
      }
    } catch {}
    try {
      const js = await RNFS.readFile(jsPath, 'utf8').catch(() => '');
      if (js) output += `=== JS file ===\n${js}\n`;
    } catch {}
    const outputPath = `${RNFS.DocumentDirectoryPath}/procamera_export_${Date.now()}.log`;
    await RNFS.writeFile(outputPath, output, 'utf8');
    return outputPath;
  },
  setFileEnabled(enabled: boolean) {
    fileEnabled = enabled;
  },
};

export function installGlobalLogger() {
  if (globalLoggerInstalled) return;
  globalLoggerInstalled = true;
  const errorUtils = (global as any).ErrorUtils;
  const previousHandler = errorUtils?.getGlobalHandler?.();
  if (errorUtils) {
    errorUtils.setGlobalHandler((error: any, isFatal?: boolean) => {
      Logger.error(`Global JS error fatal=${isFatal} ${String(error?.message || error)}`, 'JS', { stack: error?.stack });
      if (previousHandler) previousHandler(error, isFatal);
    });
  }
  try {
    const tracking = require('promise/setimmediate/rejection-tracking');
    tracking?.enable?.({
      allRejections: true,
      onUnhandled: (id: any, error: any) => {
        Logger.error(`Unhandled promise ${String(id)}`, 'JS', { message: error?.message, stack: error?.stack });
      },
    });
  } catch {}
}
