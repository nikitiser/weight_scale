package com.kicknext.weight_scale

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

class WeightScalePlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
  private lateinit var methodChannel: MethodChannel
  private lateinit var eventChannel: EventChannel
  private var weightScaleService: WeightScaleService? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.kicknext.weight_scale")
    methodChannel.setMethodCallHandler(this)

    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "com.kicknext.weight_scale/events")
    eventChannel.setStreamHandler(this)

    weightScaleService = WeightScaleService(flutterPluginBinding.applicationContext)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    weightScaleService?.closePort()
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "getDevices" -> {
        weightScaleService?.getDevices(result)
      }
      "connect" -> {
        val deviceId = call.argument<String>("deviceId")
        if (deviceId != null) {
         weightScaleService?.connect(deviceId, result)
        } else {
          result.error("INVALID_ARGUMENT", "Device ID is required", null)
        }
      }
      "disconnect" -> {
        weightScaleService?.disconnect(result)
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    weightScaleService?.setEventSink(events)
  }

  override fun onCancel(arguments: Any?) {
    weightScaleService?.setEventSink(null)
  }
}
