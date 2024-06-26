// ignore_for_file: constant_identifier_names

import 'dart:typed_data';

class ScaleProtocol {
  static const int SOH = 0x01;
  static const int STX = 0x02;
  static const int ETX = 0x03;
  static const int EOT = 0x04;

  static ScaleData parseData(Uint8List data) {
    if (data.isEmpty) {
      throw ArgumentError('No data received');
    }
    if (data.length < 16) {
      throw ArgumentError('Insufficient data received: ${data.length} bytes');
    }

    int soh = data[0];
    int stx = data[1];
    int statusByte = data[2];
    int signByte = data[3];
    String weight = String.fromCharCodes(data.sublist(4, 10));
    String weightUnits = String.fromCharCodes(data.sublist(10, 12));
    int bcc = data[12];
    int etx = data[13];
    int eot = data[14];
    int statusByte2 = data[15];

    _validateHeaders(soh, stx, etx, eot);
    _validateSignByte(signByte);
    _validateWeightUnits(weightUnits);
    _validateBcc(data, bcc);

    Status status = Status.fromByte(statusByte);
    Status2 status2 = Status2.fromByte(statusByte2);

    bool isPositive = signByte != 0x2D; // If sign byte is not '-', it's positive
    if (!isPositive) {
      // If sign byte is '-'
      weight = '-$weight';
    }

    return ScaleData(
      status: status,
      weight: weight,
      weightUnits: weightUnits,
      status2: status2,
      isPositive: isPositive,
    );
  }

  static void _validateHeaders(int soh, int stx, int etx, int eot) {
    if (soh != SOH || stx != STX || etx != ETX || eot != EOT) {
      throw const FormatException('Invalid headers in data received');
    }
  }

  static void _validateSignByte(int signByte) {
    if (signByte != 0x2D && signByte != 0x20) {
      throw const FormatException('Invalid sign character received');
    }
  }

  static void _validateWeightUnits(String weightUnits) {
    if (weightUnits.length != 2) {
      throw const FormatException('Invalid weight units received');
    }
  }

  static void _validateBcc(Uint8List data, int receivedBcc) {
    int calculatedBcc = calculateBcc(data.sublist(0, 12));
    if (receivedBcc != calculatedBcc) {
      throw const FormatException('BCC mismatch in data received');
    }
  }

  static int calculateBcc(Uint8List data) {
    int bcc = 0;
    for (var byte in data) {
      bcc ^= byte;
    }
    bcc ^= ETX;
    return bcc;
  }
}

class ScaleData {
  final Status status;
  final String weight;
  final String weightUnits;
  final Status2 status2;
  final bool isPositive;

  ScaleData({
    required this.status,
    required this.weight,
    required this.weightUnits,
    required this.status2,
    required this.isPositive,
  });

  @override
  String toString() {
    return 'Status: ${status.toString().split('.').last}, '
        'Weight: $weight $weightUnits, '
        'Status2: ${status2.toString().split('.').last}, '
        'Is Positive: $isPositive';
  }
}

enum Status {
  overload, // F (46h)
  stable, // S (53h)
  unstable, // U (55h)
  unknown; // Unknown status

  static Status fromByte(int byte) {
    switch (byte) {
      case 0x46: // 'F'
        return Status.overload;
      case 0x53: // 'S'
        return Status.stable;
      case 0x55: // 'U'
        return Status.unstable;
      default:
        return Status.unknown;
    }
  }
}

enum Status2 {
  none, // Value 0
  zero, // Value 16 (0x10)
  tare, // Value 32 (0x20)
  overload, // Value 64 (0x40)
  unknown; // Unknown status

  static Status2 fromByte(int byte) {
    switch (byte) {
      case 0:
        return Status2.none;
      case 0x10:
        return Status2.zero;
      case 0x20:
        return Status2.tare;
      case 0x40:
        return Status2.overload;
      default:
        return Status2.unknown;
    }
  }
}
