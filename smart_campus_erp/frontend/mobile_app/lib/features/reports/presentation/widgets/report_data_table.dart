
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class ReportDataTable extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const ReportDataTable({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox(height: 100, child: Center(child: Text('No detailed records found.')));

    final columns = data.first.keys.toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(AppColors.bgPrimary),
          columnSpacing: 24,
          columns: columns.map((c) => DataColumn(
            label: Text(
              c.replaceAll('_', ' ').toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary),
            ),
          )).toList(),
          rows: data.map((row) => DataRow(
            cells: columns.map((c) => DataCell(
              Text(
                '${row[c] ?? "-"}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            )).toList(),
          )).toList(),
        ),
      ),
    );
  }
}
