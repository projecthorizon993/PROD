import { NativeModules, Platform } from 'react-native';

// Android lean: expects NativeModules.ProCameraAndroid (Kotlin TFLite/GPU) if present.
// iOS module not bundled in this flavor — fallback to camera-kit capture.
const AndroidModule = NativeModules.ProCameraAndroid as any | undefined;
const IOSModule = NativeModules.ProCameraModule as any | undefined;

const ActiveModule: any | undefined = Platform.OS === 'android' ? AndroidModule : IOSModule;

export const isAvailable = Platform.OS === 'android' ? !!AndroidModule : Platform.OS === 'ios' && !!IOSModule;

const fallback = (v: any) => Promise.resolve(v);

export function capturePhoto(opts: { flash?: 'auto'|'on'|'off' } = {}): Promise<{uri: string, saved: boolean}> {
  if (!isAvailable || !ActiveModule?.capturePhoto) return fallback({ uri: '', saved: false });
  return ActiveModule.capturePhoto(opts);
}
export function startRecording(): Promise<{started: boolean}> { return isAvailable && ActiveModule?.startRecording ? ActiveModule.startRecording() : fallback({started:false}); }
export function stopRecording(): Promise<{url: string|null}> { return isAvailable && ActiveModule?.stopRecording ? ActiveModule.stopRecording() : fallback({url:null}); }
export function switchCamera(): Promise<any> { return isAvailable && ActiveModule?.switchCamera ? ActiveModule.switchCamera() : fallback({}); }
export function setZoom(zoom: number): Promise<any> { return isAvailable && ActiveModule?.setZoom ? ActiveModule.setZoom(zoom) : fallback({}); }
export function setManualExposure(iso: number, shutterMs: number): Promise<any> { return isAvailable && ActiveModule?.setManualExposure ? ActiveModule.setManualExposure(iso, shutterMs) : fallback({}); }
export function setManualFocus(pos: number): Promise<any> { return isAvailable && ActiveModule?.setManualFocus ? ActiveModule.setManualFocus(pos) : fallback({}); }
export function setWhiteBalance(r:number,g:number,b:number): Promise<any> { return isAvailable && ActiveModule?.setWhiteBalance ? ActiveModule.setWhiteBalance(r,g,b) : fallback({}); }
export type GradingParams = {
  exposure?: number; contrast?: number; saturation?: number; temperature?: number; tint?: number;
  shadows?: number; highlights?: number; vibrance?: number; hue?: number; lutIntensity?: number; enabled?: boolean;
  lift?: [number,number,number]; gamma?: [number,number,number]; gain?: [number,number,number];
};
export function setGrading(p: GradingParams): Promise<any> { return isAvailable && ActiveModule?.setGrading ? ActiveModule.setGrading(p) : fallback({}); }
export function setLUTIntensity(intensity:number): Promise<any> { return isAvailable && ActiveModule?.setLUTIntensity ? ActiveModule.setLUTIntensity(intensity) : fallback({}); }
export function listLUTs(): Promise<string[]> { return isAvailable && ActiveModule?.listLUTs ? ActiveModule.listLUTs() : fallback([]); }
export function clearLUT(): Promise<any> { return isAvailable && ActiveModule?.clearLUT ? ActiveModule.clearLUT() : fallback({}); }
export function exportPreset(): Promise<{json:string}> { return isAvailable && ActiveModule?.exportPreset ? ActiveModule.exportPreset() : fallback({json:'{}'}); }
export function importPreset(json:string): Promise<{imported:boolean}> { return isAvailable && ActiveModule?.importPreset ? ActiveModule.importPreset(json) : fallback({imported:false}); }
export function bakeLUT(name:string, size:number=33): Promise<{url:string|null,saved:boolean}> { return isAvailable && ActiveModule?.bakeLUT ? ActiveModule.bakeLUT(name,size) : fallback({url:null,saved:false}); }
export function getLUTInfo(): Promise<{name:string|null,intensity:number,enabled:boolean}> { return isAvailable && ActiveModule?.getLUTInfo ? ActiveModule.getLUTInfo() : fallback({name:null,intensity:1,enabled:true}); }
export function setFilter(name: string): Promise<any> { return isAvailable && ActiveModule?.setFilter ? ActiveModule.setFilter(name) : fallback({}); }
export function setLowLightBoost(enabled: boolean): Promise<any> { return isAvailable && ActiveModule?.setLowLightBoost ? ActiveModule.setLowLightBoost(enabled) : fallback({}); }
export function setLowLightStrategy(strategy: 'auto'|'aneRetinexformer'|'aneZeroDCE'|'retinexFallback'|'hviFallback', target: 'psnr'|'perceptual'|'natural'|'balanced'|'lpips'|'niqe'): Promise<any> { return isAvailable && ActiveModule?.setLowLightStrategy ? ActiveModule.setLowLightStrategy(strategy, target) : fallback({}); }
export function getLowLightMetrics(): Promise<{strategy:string,target:string,intensity:number,isANE:boolean}> { return isAvailable && ActiveModule?.getLowLightMetrics ? ActiveModule.getLowLightMetrics() : fallback({strategy:'auto',target:'balanced',intensity:0,isANE:false}); }
export function setSharpness(intensity: number, preset: 'auto'|'psnr'|'perceptual'|'natural'|'balanced' = 'balanced'): Promise<any> { return isAvailable && ActiveModule?.setSharpness ? ActiveModule.setSharpness(intensity, preset) : fallback({}); }
export function setSuperResolution(enabled: boolean): Promise<any> { return isAvailable && ActiveModule?.setSuperResolution ? ActiveModule.setSuperResolution(enabled) : fallback({}); }
export function getZoomInfo(): Promise<{zoom:number,min:number,max:number,opticalThreshold:number,sharpness:number,activeLens:string,seamless:boolean,switchFactors:number[],lensesBack:{id:string,label:string,nominal:number}[],isSeamlessAvailable:boolean}> { return isAvailable && ActiveModule?.getZoomInfo ? ActiveModule.getZoomInfo() : fallback({zoom:1,min:1,max:8,opticalThreshold:2.5,sharpness:0.5,activeLens:'wide',seamless:true,switchFactors:[1],lensesBack:[{id:'wide',label:'1×',nominal:1}],isSeamlessAvailable:false}); }
export function setSeamlessEnabled(enabled:boolean): Promise<any> { return isAvailable && ActiveModule?.setSeamlessEnabled ? ActiveModule.setSeamlessEnabled(enabled) : fallback({}); }
export function getLensInfo(): Promise<{activeLens:string,factors:number[],position:string,seamless:boolean,isSeamlessAvailable:boolean,lensesBack:{id:string,label:string,nominal:number}[],lensesFront:{id:string,label:string,nominal:number}[]}> { return isAvailable && ActiveModule?.getLensInfo ? ActiveModule.getLensInfo() : fallback({activeLens:'wide',factors:[1],position:'back',seamless:true,isSeamlessAvailable:false,lensesBack:[{id:'wide',label:'1×',nominal:1}],lensesFront:[]}); }
export function setBracketMode(enabled:boolean, count:number=5, iso:number=6400): Promise<any> { return isAvailable && ActiveModule?.setBracketMode ? ActiveModule.setBracketMode(enabled, count, iso) : fallback({}); }
export function getBracketInfo(): Promise<{enabled:boolean,count:number,targetISO:number,effectiveISO:number,snrGainDB:number}> { return isAvailable && ActiveModule?.getBracketInfo ? ActiveModule.getBracketInfo() : fallback({enabled:false,count:5,targetISO:6400,effectiveISO:6400,snrGainDB:0}); }
export function loadLUT(path: string): Promise<{loaded:boolean}> { return isAvailable && ActiveModule?.loadLUT ? ActiveModule.loadLUT(path) : fallback({loaded:false}); }

export const Filters = ['None','Vivid','Vivid Warm','Mono','Noir','Silver','Chrome','Fade','Instant','Process','Transfer','Tonal','Cinematic','Teal & Orange','Night Boost'] as const;
export const LowLightStrategies = ['auto','aneRetinexformer','aneZeroDCE','retinexFallback','hviFallback'] as const;
export const MetricTargets = ['psnr','perceptual','natural','balanced'] as const;
