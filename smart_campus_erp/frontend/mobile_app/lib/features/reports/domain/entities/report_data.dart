
import 'package:equatable/equatable.dart';

enum ReportType {
  attendance,
  student,
  teacher,
  department,
  subject,
  defaulter,
  audit,
  analytics
}

class ReportSummary extends Equatable {
  final String title;
  final String value;
  final double trend; // e.g. +5.2
  final bool isPositive;

  const ReportSummary({
    required this.title,
    required this.value,
    this.trend = 0.0,
    this.isPositive = true,
  });

  @override
  List<Object?> get props => [title, value, trend, isPositive];
}

class ChartDataPoint extends Equatable {
  final String label;
  final double value;

  const ChartDataPoint(this.label, this.value);

  @override
  List<Object?> get props => [label, value];
}
