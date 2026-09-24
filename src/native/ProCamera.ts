import { NativeModules, Platform } from 'react-native';

const LINKING_ERROR = `ProCameraModule not linked. Run pod install and rebuild.`;

const ProCameraModule = NativeModules.ProCameraModule
  ? NativeModules.ProCameraModule
  : new Proxy({}, { get() { throw new Error(LINKING_ERROR); } });

export const isAvailable = Platform.OS === 'ios' && !!NativeModules.ProCameraModule;

export function capturePhoto(opts: { flash?: 'auto'|'on'|'off' } = {}): Promise<{uri: string, saved: boolean}> {
  if (!isAvailable) return Promise.resolve({ uri: '', saved: false });
  return ProCameraModule.capturePhoto(opts);
}
export function startRecording(): Promise<{started: boolean}> { return isAvailable ? ProCameraModule.startRecording() : Promise.resolve({started:false}); }
export function stopRecording(): Promise<{url: string|null}> { return isAvailable ? ProCameraModule.stopRecording() : Promise.resolve({url:null}); }
export function switchCamera(): Promise<any> { return isAvailable ? ProCameraModule.switchCamera() : Promise.resolve({}); }
export function setZoom(zoom: number): Promise<any> { return isAvailable ? ProCameraModule.setZoom(zoom) : Promise.resolve({}); }
export function setManualExposure(iso: number, shutterMs: number): Promise<any> { return isAvailable ? ProCameraModule.setManualExposure(iso, shutterMs) : Promise.resolve({}); }
export function setManualFocus(pos: number): Promise<any> { return isAvailable ? ProCameraModule.setManualFocus(pos) : Promise.resolve({}); }
export function setWhiteBalance(r:number,g:number,b:number): Promise<any> { return isAvailable ? ProCameraModule.setWhiteBalance(r,g,b) : Promise.resolve({}); }
export type GradingParams = {
  exposure?: number; contrast?: number; saturation?: number; temperature?: number; tint?: number;
  shadows?: number; highlights?: number; vibrance?: number; hue?: number; lutIntensity?: number; enabled?: boolean;
  lift?: [number,number,number]; gamma?: [number,number,number]; gain?: [number,number,number];
};
export function setGrading(p: GradingParams): Promise<any> { return isAvailable ? ProCameraModule.setGrading(p) : Promise.resolve({}); }
export function setLUTIntensity(intensity:number): Promise<any> { return isAvailable ? ProCameraModule.setLUTIntensity(intensity) : Promise.resolve({}); }
export function listLUTs(): Promise<string[]> { return isAvailable ? ProCameraModule.listLUTs() : Promise.resolve([]); }
export function clearLUT(): Promise<any> { return isAvailable ? ProCameraModule.clearLUT() : Promise.resolve({}); }
export function exportPreset(): Promise<{json:string}> { return isAvailable ? ProCameraModule.exportPreset() : Promise.resolve({json:'{}'}); }
export function importPreset(json:string): Promise<{imported:boolean}> { return isAvailable ? ProCameraModule.importPreset(json) : Promise.resolve({imported:false}); }
export function bakeLUT(name:string, size:number=33): Promise<{url:string|null,saved:boolean}> { return isAvailable ? ProCameraModule.bakeLUT(name,size) : Promise.resolve({url:null,saved:false}); }
export function getLUTInfo(): Promise<{name:string|null,intensity:number,enabled:boolean}> { return isAvailable ? ProCameraModule.getLUTInfo() : Promise.resolve({name:null,intensity:1,enabled:true}); }
export function setFilter(name: string): Promise<any> { return isAvailable ? ProCameraModule.setFilter(name) : Promise.resolve({}); }
export function setLowLightBoost(enabled: boolean): Promise<any> { return isAvailable ? ProCameraModule.setLowLightBoost(enabled) : Promise.resolve({}); }
export function setLowLightStrategy(strategy: 'auto'|'aneRetinexformer'|'aneZeroDCE'|'retinexFallback'|'hviFallback', target: 'psnr'|'perceptual'|'natural'|'balanced'|'lpips'|'niqe'): Promise<any> { return isAvailable ? ProCameraModule.setLowLightStrategy(strategy, target) : Promise.resolve({}); }
export function getLowLightMetrics(): Promise<{strategy:string,target:string,intensity:number,isANE:boolean}> { return isAvailable ? ProCameraModule.getLowLightMetrics() : Promise.resolve({strategy:'auto',target:'balanced',intensity:0,isANE:false}); }
export function setSharpness(intensity: number, preset: 'auto'|'psnr'|'perceptual'|'natural'|'balanced' = 'balanced'): Promise<any> { return isAvailable ? ProCameraModule.setSharpness(intensity, preset) : Promise.resolve({}); }
export function setSuperResolution(enabled: boolean): Promise<any> { return isAvailable ? ProCameraModule.setSuperResolution(enabled) : Promise.resolve({}); }
export function getZoomInfo(): Promise<{zoom:number,min:number,max:number,opticalThreshold:number,sharpness:number,activeLens:string,seamless:boolean,switchFactors:number[],lensesBack:{id:string,label:string,nominal:number}[],isSeamlessAvailable:boolean}> { return isAvailable ? ProCameraModule.getZoomInfo() : Promise.resolve({zoom:1,min:1,max:8,opticalThreshold:2.5,sharpness:0.5,activeLens:'wide',seamless:true,switchFactors:[1],lensesBack:[{id:'wide',label:'1×',nominal:1}],isSeamlessAvailable:false}); }
export function setSeamlessEnabled(enabled:boolean): Promise<any> { return isAvailable ? ProCameraModule.setSeamlessEnabled(enabled) : Promise.resolve({}); }
export function getLensInfo(): Promise<{activeLens:string,factors:number[],position:string,seamless:boolean,isSeamlessAvailable:boolean,lensesBack:{id:string,label:string,nominal:number}[],lensesFront:{id:string,label:string,nominal:number}[]}> { return isAvailable ? ProCameraModule.getLensInfo() : Promise.resolve({activeLens:'wide',factors:[1],position:'back',seamless:true,isSeamlessAvailable:false,lensesBack:[{id:'wide',label:'1×',nominal:1}],lensesFront:[]}); }
export function setBracketMode(enabled:boolean, count:number=5, iso:number=6400): Promise<any> { return isAvailable ? ProCameraModule.setBracketMode(enabled, count, iso) : Promise.resolve({}); }
export function getBracketInfo(): Promise<{enabled:boolean,count:number,targetISO:number,effectiveISO:number,snrGainDB:number}> { return isAvailable ? ProCameraModule.getBracketInfo() : Promise.resolve({enabled:false,count:5,targetISO:6400,effectiveISO:6400,snrGainDB:0}); }
export function loadLUT(path: string): Promise<{loaded:boolean}> { return isAvailable ? ProCameraModule.loadLUT(path) : Promise.resolve({loaded:false}); }
export function logMessage(msg: string): Promise<any> { return isAvailable && (ProCameraModule as any).logMessage ? (ProCameraModule as any).logMessage(msg) : Promise.resolve({}); }
export function getLogs(): Promise<string> { return isAvailable && (ProCameraModule as any).getLogs ? (ProCameraModule as any).getLogs() : Promise.resolve(''); }
export function clearLogs(): Promise<any> { return isAvailable && (ProCameraModule as any).clearLogs ? (ProCameraModule as any).clearLogs() : Promise.resolve({}); }
export function getLogFilePath(): Promise<string> { return isAvailable && (ProCameraModule as any).getLogFilePath ? (ProCameraModule as any).getLogFilePath() : Promise.resolve(''); }

export const Filters = ['None','Vivid','Vivid Warm','Mono','Noir','Silver','Chrome','Fade','Instant','Process','Transfer','Tonal','Cinematic','Teal & Orange','Night Boost'] as const;
export const LowLightStrategies = ['auto','aneRetinexformer','aneZeroDCE','retinexFallback','hviFallback'] as const;
export const MetricTargets = ['psnr','perceptual','natural','balanced'] as const;
