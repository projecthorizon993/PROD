package com.camerapp

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.WritableMap
import com.facebook.react.bridge.Arguments

class ProCameraModule(private val reactContext: ReactApplicationContext) : ReactContextBaseJavaModule(reactContext) {
    override fun getName(): String = "ProCameraAndroid"

    // Photo — fallback to CameraKit capture handled in JS, native just acknowledges
    @ReactMethod
    fun capturePhoto(options: com.facebook.react.bridge.ReadableMap?, promise: Promise) {
        val map = Arguments.createMap()
        map.putString("uri", "")
        map.putBoolean("saved", false)
        promise.resolve(map)
    }

    @ReactMethod
    fun startRecording(promise: Promise) {
        val map = Arguments.createMap(); map.putBoolean("started", false); promise.resolve(map)
    }

    @ReactMethod
    fun stopRecording(promise: Promise) {
        val map = Arguments.createMap(); map.putNull("url"); promise.resolve(map)
    }

    @ReactMethod
    fun switchCamera(promise: Promise) { promise.resolve(Arguments.createMap()) }
    @ReactMethod
    fun setZoom(zoom: Double, promise: Promise) { promise.resolve(Arguments.createMap()) }
    @ReactMethod
    fun setManualExposure(iso: Double, shutterMs: Double, promise: Promise) { promise.resolve(Arguments.createMap()) }
    @ReactMethod
    fun setManualFocus(pos: Double, promise: Promise) { promise.resolve(Arguments.createMap()) }
    @ReactMethod
    fun setWhiteBalance(r: Double, g: Double, b: Double, promise: Promise) { promise.resolve(Arguments.createMap()) }
    @ReactMethod
    fun setGrading(params: com.facebook.react.bridge.ReadableMap?, promise: Promise) { promise.resolve(Arguments.createMap()) }
    @ReactMethod
    fun setLUTIntensity(intensity: Double, promise: Promise) { promise.resolve(Arguments.createMap()) }
    @ReactMethod
    fun listLUTs(promise: Promise) { promise.resolve(Arguments.createArray()) }
    @ReactMethod
    fun clearLUT(promise: Promise) { promise.resolve(Arguments.createMap()) }
    @ReactMethod
    fun exportPreset(promise: Promise) { val m = Arguments.createMap(); m.putString("json","{}"); promise.resolve(m) }
    @ReactMethod
    fun importPreset(json: String?, promise: Promise) { val m = Arguments.createMap(); m.putBoolean("imported", false); promise.resolve(m) }
    @ReactMethod
    fun bakeLUT(name: String?, size: Double, promise: Promise) { val m = Arguments.createMap(); m.putNull("url"); m.putBoolean("saved",false); promise.resolve(m) }
    @ReactMethod
    fun getLUTInfo(promise: Promise) { val m = Arguments.createMap(); m.putNull("name"); m.putDouble("intensity",1.0); m.putBoolean("enabled",true); promise.resolve(m) }
    @ReactMethod
    fun setFilter(name: String?, promise: Promise) { promise.resolve(Arguments.createMap()) }
    @ReactMethod
    fun setLowLightBoost(enabled: Boolean, promise: Promise) { promise.resolve(Arguments.createMap()) }
    @ReactMethod
    fun setLowLightStrategy(strategy: String?, target: String?, promise: Promise) { promise.resolve(Arguments.createMap()) }
    @ReactMethod
    fun getLowLightMetrics(promise: Promise) { val m = Arguments.createMap(); m.putString("strategy","auto"); m.putString("target","balanced"); m.putDouble("intensity",0.0); m.putBoolean("isANE",false); promise.resolve(m) }
    @ReactMethod
    fun setSharpness(intensity: Double, preset: String?, promise: Promise) { promise.resolve(Arguments.createMap()) }
    @ReactMethod
    fun setSuperResolution(enabled: Boolean, promise: Promise) { promise.resolve(Arguments.createMap()) }
    @ReactMethod
    fun getZoomInfo(promise: Promise) {
        val m = Arguments.createMap()
        m.putDouble("zoom",1.0); m.putDouble("min",1.0); m.putDouble("max",8.0); m.putDouble("opticalThreshold",2.5); m.putDouble("sharpness",0.5)
        m.putString("activeLens","wide"); m.putBoolean("seamless",true)
        val arr = Arguments.createArray(); arr.pushDouble(1.0); m.putArray("switchFactors",arr)
        val lenses = Arguments.createArray(); val lens = Arguments.createMap(); lens.putString("id","wide"); lens.putString("label","1×"); lens.putDouble("nominal",1.0); lenses.pushMap(lens); m.putArray("lensesBack",lenses)
        m.putBoolean("isSeamlessAvailable",false)
        promise.resolve(m)
    }
    @ReactMethod
    fun setSeamlessEnabled(enabled: Boolean, promise: Promise) { promise.resolve(Arguments.createMap()) }
    @ReactMethod
    fun getLensInfo(promise: Promise) {
        val m = Arguments.createMap(); m.putString("activeLens","wide")
        val arr = Arguments.createArray(); arr.pushDouble(1.0); m.putArray("factors",arr)
        m.putString("position","back"); m.putBoolean("seamless",true); m.putBoolean("isSeamlessAvailable",false)
        val back = Arguments.createArray(); val lens = Arguments.createMap(); lens.putString("id","wide"); lens.putString("label","1×"); lens.putDouble("nominal",1.0); back.pushMap(lens); m.putArray("lensesBack",back)
        m.putArray("lensesFront", Arguments.createArray())
        promise.resolve(m)
    }
    @ReactMethod
    fun setBracketMode(enabled: Boolean, count: Double, iso: Double, promise: Promise) {
        val m = Arguments.createMap(); m.putBoolean("bracket",enabled); m.putDouble("count",count); m.putDouble("iso",iso); m.putDouble("effectiveGainDB",0.0); promise.resolve(m)
    }
    @ReactMethod
    fun getBracketInfo(promise: Promise) {
        val m = Arguments.createMap(); m.putBoolean("enabled",false); m.putDouble("count",5.0); m.putDouble("targetISO",6400.0); m.putDouble("effectiveISO",6400.0); m.putDouble("snrGainDB",0.0); promise.resolve(m)
    }
    @ReactMethod
    fun loadLUT(path: String?, promise: Promise) { val m = Arguments.createMap(); m.putBoolean("loaded",false); promise.resolve(m) }
}
