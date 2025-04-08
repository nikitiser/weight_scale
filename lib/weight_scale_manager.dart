import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:weight_scale/protocol.dart';
import 'package:weight_scale/weight_scale_device.dart';

class WeightScaleManager {
  static const MethodChannel _methodChannel =
      MethodChannel('com.kicknext.weight_scale');
  static const EventChannel _eventChannel =
      EventChannel('com.kicknext.weight_scale/events');

  static final WeightScaleManager _instance = WeightScaleManager._internal();
  factory WeightScaleManager() => _instance;
  WeightScaleManager._internal();

  // Список известных VID/PID весов
  static const List<Map<String, String>> _knownScaleIDs = [
    {
      'vendorID': '0x1a86', // Aclas VID
      'productID': '0x7523', // Aclas PID
      'name': 'Aclas',
    },
    // Сюда можно добавить другие модели весов
    // {'vendorID': 'VID_ДРУГОЙ', 'productID': 'PID_ДРУГОЙ', 'name': 'Другая Модель'},
  ];

  WeightScaleDevice? _connectedDevice;
  Stream<ScaleData>? _dataStream;
  StreamSubscription<ScaleData>? _dataSubscription;

  // Callback for error handling
  void Function(Object error, StackTrace stackTrace)? onErrorCallback;

  // Get list of connected devices
  Future<List<WeightScaleDevice>> getDevices() async {
    try {
      final devices = await _methodChannel
          .invokeMethod<Map<dynamic, dynamic>>('getDevices');
      if (devices == null) return [];

      List<WeightScaleDevice> deviceList = devices.entries.map((entry) {
        final deviceInfo = (entry.value as String).split(':');
        return WeightScaleDevice(
          deviceName: entry.key as String,
          vendorID: deviceInfo[0],
          productID: deviceInfo[1],
        );
      }).toList();

      return await _filterValidDevices(deviceList);
    } on PlatformException catch (e, stackTrace) {
      _handleError(e, stackTrace, 'getDevices');
      return [];
    }
  }

  Future<List<WeightScaleDevice>> _filterValidDevices(
      List<WeightScaleDevice> devices) async {
    List<WeightScaleDevice> validDevices = [];
    _debugPrint('WeightScaleManager: Starting device filtering. Total devices found: ${devices.length}');

    for (var device in devices) {
      _debugPrint('WeightScaleManager: Checking device: ${device.deviceName} (VID: ${device.vendorID}, PID: ${device.productID})');

      // Проверяем, есть ли VID/PID устройства в нашем списке известных весов
      bool isKnownScale = _knownScaleIDs.any((id) =>
          id['vendorID'] == device.vendorID &&
          id['productID'] == device.productID);

      if (isKnownScale) {
        _debugPrint('WeightScaleManager: Device ${device.deviceName} is a known scale. Proceeding with check...');
        // Только если VID/PID совпали, выполняем проверку подключения
        if (await _checkDevice(device)) {
          _debugPrint('WeightScaleManager: Device check successful for ${device.deviceName}. Adding to valid list.');
          validDevices.add(device);
        } else {
          _debugPrint('WeightScaleManager: Device check failed for ${device.deviceName}.');
        }
      } else {
         _debugPrint('WeightScaleManager: Skipping device ${device.deviceName} - not a known scale.');
      }
    }
    _debugPrint('WeightScaleManager: Filtering complete. Found ${validDevices.length} valid scale devices.');
    return validDevices;
  }

  // Connect to a device
  Future<void> connect(WeightScaleDevice device) async {
    try {
      await _methodChannel.invokeMethod('connect', {
        "deviceName": device.deviceName,
        "vendorID": device.vendorID,
        "productID": device.productID,
      });
      device.isConnected = true;
      _connectedDevice = device;

      // Initialize data stream
      _initializeDataStream();
    } on PlatformException catch (e, stackTrace) {
      _handleError(e, stackTrace, 'connect');
      device.isConnected = false;
    }
  }

  // Disconnect from the device
  Future<void> disconnect() async {
    try {
      await _methodChannel.invokeMethod('disconnect');
      _connectedDevice?.isConnected = false;
      _connectedDevice = null;

      // Cancel data stream subscription and clear data stream
      await _dataSubscription?.cancel();
      _dataSubscription = null;
      _dataStream = null;
    } on PlatformException catch (e, stackTrace) {
      _handleError(e, stackTrace, 'disconnect');
    }
  }

  // Initialize data stream
  void _initializeDataStream() {
    _dataStream = _eventChannel
        .receiveBroadcastStream()
        .map(_parseEvent)
        .where((event) => event != null)
        .cast<ScaleData>();

    // Subscribe to the data stream
    _dataSubscription = _dataStream!.listen((data) {
      // Handle incoming data
      _debugPrint('WeightScaleManager: Received data: $data');
    }, onError: (error, stackTrace) {
      _handleError(error, stackTrace, '_initializeDataStream');
    });
  }

  ScaleData? _parseEvent(dynamic event) {
    if (event is Uint8List) {
      try {
        return ScaleProtocol.parseData(event);
      } catch (e, stackTrace) {
        _handleError(e, stackTrace, '_parseEvent');
        return null;
      }
    } else {
      _handleError(const FormatException("Received unknown data format"),
          StackTrace.current, '_parseEvent');
      return null;
    }
  }

  // Get a stream of data from the device
  Stream<ScaleData>? get dataStream => _dataStream;

  // Get the connected device
  WeightScaleDevice? get connectedDevice => _connectedDevice;

  // Check if a device is connected
  bool get isConnected => _connectedDevice != null;

  // Check if the device sends data within 500 ms
  Future<bool> _checkDevice(WeightScaleDevice device) async {
     _debugPrint('WeightScaleManager: _checkDevice started for ${device.deviceName}');
    final completer = Completer<bool>();
    StreamSubscription? subscription; // Объявляем здесь, чтобы был доступен в catch и finally

    try {
      // Попытка подключения к устройству
      await connect(device);

      // Проверяем, успешно ли прошло подключение перед подпиской на стрим
      if (_connectedDevice?.deviceName != device.deviceName) {
        _debugPrint('WeightScaleManager: _checkDevice connection failed early for ${device.deviceName}');
        if (!completer.isCompleted) {
           completer.complete(false);
        }
        return completer.future; // Выходим, если подключение не удалось
      }

      // Слушаем данные и завершаем future, если данные получены
      subscription = dataStream?.listen((data) {
         _debugPrint('WeightScaleManager: _checkDevice received data for ${device.deviceName}');
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      }, onError: (err, stack) { // Обрабатываем ошибку стрима
         _debugPrint('WeightScaleManager: _checkDevice stream error for ${device.deviceName}: $err');
         if (!completer.isCompleted) {
            completer.complete(false);
         }
      });

      // Завершаем future с false, если данные не получены в течение 500 мс
      Future.delayed(const Duration(milliseconds: 500), () async {
        if (!completer.isCompleted) {
           _debugPrint('WeightScaleManager: _checkDevice timed out for ${device.deviceName}');
          completer.complete(false);
        }
        // Отписка происходит в finally
      });

    } catch (e, stackTrace) {
       _debugPrint('WeightScaleManager: _checkDevice connection error during connect() for ${device.deviceName}: $e');
       _handleError(e, stackTrace, '_checkDevice/connect');
       if (!completer.isCompleted) {
          completer.complete(false);
       }
    } finally {
       // Гарантированная отписка и отключение
       await subscription?.cancel();
       // Отключаемся ТОЛЬКО если это устройство все еще числится подключенным
       if (_connectedDevice?.deviceName == device.deviceName) {
          _debugPrint('WeightScaleManager: _checkDevice disconnecting from ${device.deviceName} in finally block.');
          await disconnect();
       } else {
          _debugPrint('WeightScaleManager: _checkDevice - skipping disconnect in finally as device ${device.deviceName} is not the currently connected one ($_connectedDevice).');
       }
    }

    final result = await completer.future;
    _debugPrint('WeightScaleManager: _checkDevice finished for ${device.deviceName}. Result: $result');
    return result;
  }

  // Handle errors
  void _handleError(Object error, StackTrace stackTrace, String context) {
    _debugPrint(
        'WeightScaleManager: Error in $context: $error\nStack trace: $stackTrace');
    onErrorCallback?.call(error, stackTrace);
  }

  void _debugPrint(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
