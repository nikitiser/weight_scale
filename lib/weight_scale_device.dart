class WeightScaleDevice {
  final String deviceName;
  final String vendorID;
  final String productID;
  bool isConnected;

  WeightScaleDevice({
    required this.deviceName,
    required this.vendorID,
    required this.productID,
    this.isConnected = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'deviceName': deviceName,
      'vendorID': vendorID,
      'productID': productID,
    };
  }

  factory WeightScaleDevice.fromJson(Map<String, dynamic> json) {
    return WeightScaleDevice(
      deviceName: json['deviceName'],
      vendorID: json['vendorID'],
      productID: json['productID'],
    );
  }

  @override
  String toString() {
    return 'WeightScaleDevice(deviceName: $deviceName, vendorID: $vendorID, productID: $productID, isConnected: $isConnected)';
  }

  static List<WeightScaleDevice> listFromJson(List<dynamic> jsonList) {
    return jsonList.map((json) => WeightScaleDevice.fromJson(json)).toList();
  }

  static List<Map<String, dynamic>> listToJson(
      List<WeightScaleDevice> deviceList) {
    return deviceList.map((device) => device.toJson()).toList();
  }
}
