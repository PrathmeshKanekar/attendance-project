import 'package:equatable/equatable.dart';

class CornerData extends Equatable {
  final double lat;
  final double lng;
  final double alt;
  final double heading;
  final double accuracy;
  final DateTime? timestamp;
  final String? label;

  const CornerData({
    required this.lat,
    required this.lng,
    required this.alt,
    required this.heading,
    required this.accuracy,
    this.timestamp,
    this.label,
  });

  factory CornerData.fromJson(Map<String, dynamic> json) {
    return CornerData(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      alt: (json['alt'] as num).toDouble(),
      heading: (json['heading'] as num?)?.toDouble() ?? 0.0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp']) : null,
      label: json['label'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'alt': alt,
    'heading': heading,
    'accuracy': accuracy,
    if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
    if (label != null) 'label': label,
  };

  CornerData copyWith({
    double? lat,
    double? lng,
    double? alt,
    double? heading,
    double? accuracy,
    DateTime? timestamp,
    String? label,
  }) {
    return CornerData(
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      alt: alt ?? this.alt,
      heading: heading ?? this.heading,
      accuracy: accuracy ?? this.accuracy,
      timestamp: timestamp ?? this.timestamp,
      label: label ?? this.label,
    );
  }

  @override
  List<Object?> get props => [lat, lng, alt, heading, accuracy, timestamp, label];
}
