import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/services/medication_log_service.dart';

class PDFService {  static Future<Uint8List> generateMedicationReport({
    required List<Map<String, dynamic>> logs,
    required Map<String, int> stats,
    String? patientName,
    String? patientId,
    String? doctorName,
  }) async {
    try {
      final pdf = pw.Document();
      
      // SAFETY: Limit the number of logs to prevent excessive PDF size
      const maxLogsForPDF = 200; // Limit to 200 most recent logs
      final limitedLogs = logs.length > maxLogsForPDF 
          ? logs.take(maxLogsForPDF).toList()
          : logs;
      
      print('PDF Generation: Processing ${limitedLogs.length} logs (limited from ${logs.length})');
      
      // Get current date for report
      final now = DateTime.now();
      final dateFormatter = DateFormat('MMMM dd, yyyy');
      final timeFormatter = DateFormat('h:mm a');
      
      // Calculate adherence rate
      final totalMedications = stats['total'] ?? 0;
      final takenMedications = stats['taken'] ?? 0;
      final adherenceRate = totalMedications > 0 
          ? (takenMedications / totalMedications * 100).round() 
          : 0;
      
      // Group logs by date for better organization (using limited logs)
      final groupedLogs = _groupLogsByDate(limitedLogs);
      
      // Calculate weekly stats (using limited logs)
      final weeklyStats = _calculateWeeklyStats(limitedLogs);
      
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          maxPages: 20, // SAFETY: Limit maximum pages to prevent excessive generation
          build: (pw.Context context) {
            return [
              // Header Section
              _buildHeader(patientName, patientId, doctorName, now, dateFormatter, timeFormatter),
              pw.SizedBox(height: 30),
              
              // Summary Statistics
              _buildSummarySection(stats, adherenceRate),
              pw.SizedBox(height: 30),
              
              // Weekly Performance
              _buildWeeklyPerformanceSection(weeklyStats),
              pw.SizedBox(height: 30),
              
              // Detailed Logs Section (limited data)
              _buildDetailedLogsSection(groupedLogs),
              
              // Footer with disclaimers
              pw.SizedBox(height: 30),
              _buildFooter(),
              
              // Data limitation notice if original logs were truncated
              if (logs.length > maxLogsForPDF) ...[
                pw.SizedBox(height: 20),
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.orange50,
                    border: pw.Border.all(color: PdfColors.orange200),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'DATA LIMITATION NOTICE',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.orange800,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'This report shows ${limitedLogs.length} of your most recent medication logs out of ${logs.length} total logs. For complete historical data, please refer to the app.',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.orange700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ];
          },
        ),
      );

      return pdf.save();
      
    } catch (e) {
      print('Error generating PDF: $e');
      // Return a minimal error PDF instead of crashing
      final errorPdf = pw.Document();
      errorPdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    'PDF Generation Error',
                    style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    'Unable to generate the medication report due to data processing issues.',
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'Please try again or contact support if the issue persists.',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                  ),
                ],
              ),
            );
          },
        ),
      );
      return errorPdf.save();
    }
  }

  static pw.Widget _buildHeader(String? patientName, String? patientId, 
      String? doctorName, DateTime now, DateFormat dateFormatter, DateFormat timeFormatter) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'MEDICATION ADHERENCE REPORT',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue800,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'Generated on ${dateFormatter.format(now)} at ${timeFormatter.format(now)}',
                  style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                ),
              ],
            ),
            pw.Container(
              width: 80,
              height: 80,
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(40),
                border: pw.Border.all(color: PdfColors.blue200, width: 2),
              ),
              child: pw.Center(
                child: pw.Text(
                  'CURE\nCUE',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue800,
                  ),
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: PdfColors.grey300),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'PATIENT INFORMATION',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey800,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      'Patient Name: ${patientName ?? 'Not Specified'}',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      'Patient ID: ${patientId ?? 'Not Specified'}',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (doctorName != null) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  'Primary Care Physician: $doctorName',
                  style: const pw.TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSummarySection(Map<String, int> stats, int adherenceRate) {
    final totalMedications = stats['total'] ?? 0;
    final takenMedications = stats['taken'] ?? 0;
    final missedMedications = stats['forgot'] ?? 0;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'ADHERENCE SUMMARY',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue800,
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          children: [
            _buildStatCard('Total Medications', totalMedications.toString(), PdfColors.blue),
            pw.SizedBox(width: 16),
            _buildStatCard('Taken', takenMedications.toString(), PdfColors.green),
            pw.SizedBox(width: 16),
            _buildStatCard('Missed', missedMedications.toString(), PdfColors.red),
            pw.SizedBox(width: 16),
            _buildStatCard('Adherence Rate', '$adherenceRate%', 
                adherenceRate >= 80 ? PdfColors.green : adherenceRate >= 60 ? PdfColors.orange : PdfColors.red),
          ],
        ),
        pw.SizedBox(height: 16),
        _buildAdherenceInsight(adherenceRate),
      ],
    );
  }

  static pw.Widget _buildStatCard(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          color: color.shade(0.1),
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: color.shade(0.3)),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildAdherenceInsight(int adherenceRate) {
    String insight;
    PdfColor color;
    
    if (adherenceRate >= 90) {
      insight = "Excellent adherence! You're maintaining a very high level of medication compliance.";
      color = PdfColors.green;
    } else if (adherenceRate >= 80) {
      insight = "Good adherence! You're doing well with your medication routine.";
      color = PdfColors.green;
    } else if (adherenceRate >= 60) {
      insight = "Moderate adherence. Consider setting more reminders to improve consistency.";
      color = PdfColors.orange;
    } else {
      insight = "Low adherence detected. Please consult with your healthcare provider about strategies to improve medication compliance.";
      color = PdfColors.red;
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: color.shade(0.1),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: color.shade(0.3)),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 4,
            height: 40,
            decoration: pw.BoxDecoration(
              color: color,
              borderRadius: pw.BorderRadius.circular(2),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Text(
              insight,
              style: pw.TextStyle(
                fontSize: 12,
                color: PdfColors.grey800,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildWeeklyPerformanceSection(Map<String, Map<String, int>> weeklyStats) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'WEEKLY PERFORMANCE',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue800,
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                _buildTableCell('Week', isHeader: true),
                _buildTableCell('Total', isHeader: true),
                _buildTableCell('Taken', isHeader: true),
                _buildTableCell('Missed', isHeader: true),
                _buildTableCell('Rate', isHeader: true),
              ],
            ),
            ...weeklyStats.entries.map((entry) {
              final week = entry.key;
              final stats = entry.value;
              final total = stats['total'] ?? 0;
              final taken = stats['taken'] ?? 0;
              final missed = stats['forgot'] ?? 0;
              final rate = total > 0 ? (taken / total * 100).round() : 0;
              
              return pw.TableRow(
                children: [
                  _buildTableCell(week),
                  _buildTableCell(total.toString()),
                  _buildTableCell(taken.toString()),
                  _buildTableCell(missed.toString()),
                  _buildTableCell('$rate%'),
                ],
              );
            }).toList(),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTableCell(String text, {bool isHeader = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 12 : 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.grey800 : PdfColors.grey700,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }
  static pw.Widget _buildDetailedLogsSection(Map<String, List<Map<String, dynamic>>> groupedLogs) {
    // SAFETY: Further limit data to prevent PDF overflow
    const maxDaysToShow = 7; // Show maximum 7 days
    const maxLogsPerDay = 10; // Show maximum 10 logs per day
    
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'DETAILED MEDICATION LOGS',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue800,
          ),
        ),
        pw.SizedBox(height: 16),
        ...groupedLogs.entries.take(maxDaysToShow).map((entry) { 
          final date = entry.key;
          final dayLogs = entry.value.take(maxLogsPerDay).toList(); // Limit logs per day
          
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      date,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    if (entry.value.length > maxLogsPerDay)
                      pw.Text(
                        '(${dayLogs.length} of ${entry.value.length} logs shown)',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                          fontStyle: pw.FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),...dayLogs.map((log) {
                final action = log['action']?.toString() ?? 'unknown';
                final color = action == 'taken' ? PdfColors.green : PdfColors.red;
                final icon = action == 'taken' ? '✓' : '✗';
                
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 4),
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Container(
                        width: 20,
                        height: 20,
                        decoration: pw.BoxDecoration(
                          color: color,
                          borderRadius: pw.BorderRadius.circular(10),
                        ),
                        child: pw.Center(
                          child: pw.Text(
                            icon,
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [                            pw.Text(
                              log['medicineName']?.toString() ?? 'Unknown Medication',
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.Text(
                              'Reminder: ${_formatTime(log['reminderTime']?.toString())} • Action: ${_formatTime(log['actionTime']?.toString())}',
                              style: pw.TextStyle(
                                fontSize: 10,
                                color: PdfColors.grey600,
                              ),
                            ),
                          ],
                        ),
                      ),                      pw.Text(
                        action.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              pw.SizedBox(height: 16),
            ],
          );        }).toList(),
        if (groupedLogs.length > 7)
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              'Note: Only the 7 most recent days are shown in this report (maximum 10 logs per day). For complete logs, please check the app.',
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey600,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey300),
        pw.SizedBox(height: 16),
        pw.Text(
          'IMPORTANT DISCLAIMERS',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey800,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          '• This report is generated based on user-reported data and may not reflect actual medication consumption.\n'
          '• Please consult with your healthcare provider before making any changes to your medication regimen.\n'
          '• This app is not a substitute for professional medical advice, diagnosis, or treatment.\n'
          '• In case of medical emergencies, contact your healthcare provider immediately.',
          style: pw.TextStyle(
            fontSize: 10,
            color: PdfColors.grey600,
            height: 1.4,
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Center(
          child: pw.Text(
            'Generated by CureCue Medical Assistant App',
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey500,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }  // Helper method to group logs by date
  static Map<String, List<Map<String, dynamic>>> _groupLogsByDate(List<Map<String, dynamic>> logs) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    final dateFormatter = DateFormat('EEEE, MMMM dd, yyyy');
    
    for (final log in logs) {
      final actionTime = log['actionTime'];
      if (actionTime == null) continue;
      
      try {
        final dateTime = DateTime.parse(actionTime.toString());
        final dateKey = dateFormatter.format(dateTime);
        
        if (!grouped.containsKey(dateKey)) {
          grouped[dateKey] = [];
        }
        grouped[dateKey]!.add(log);
      } catch (e) {
        print('Error parsing date: $actionTime - $e');
        continue;
      }
    }
    
    return grouped;
  }  // Helper method to calculate weekly stats
  static Map<String, Map<String, int>> _calculateWeeklyStats(List<Map<String, dynamic>> logs) {
    final Map<String, Map<String, int>> weeklyStats = {};
    
    for (final log in logs) {
      final actionTime = log['actionTime'];
      if (actionTime == null) continue;
      
      try {
        final dateTime = DateTime.parse(actionTime.toString());
        final weekStart = dateTime.subtract(Duration(days: dateTime.weekday - 1));
        final weekKey = 'Week of ${DateFormat('MMM dd').format(weekStart)}';
        
        if (!weeklyStats.containsKey(weekKey)) {
          weeklyStats[weekKey] = {'total': 0, 'taken': 0, 'missed': 0};
        }
        
        weeklyStats[weekKey]!['total'] = (weeklyStats[weekKey]!['total']! + 1);
        final action = log['action']?.toString();
        if (action == 'taken') {
          weeklyStats[weekKey]!['taken'] = (weeklyStats[weekKey]!['taken']! + 1);
        } else {
          weeklyStats[weekKey]!['missed'] = (weeklyStats[weekKey]!['missed']! + 1);
        }
      } catch (e) {
        print('Error parsing date in weekly stats: $actionTime - $e');
        continue;
      }
    }
    
    return weeklyStats;
  }
  // Helper method to format time
  static String _formatTime(String? timeString) {
    if (timeString == null || timeString.isEmpty) return 'Unknown time';
    try {
      final dateTime = DateTime.parse(timeString);
      return DateFormat('h:mm a').format(dateTime);
    } catch (e) {
      return timeString;
    }
  }

  // Method to save PDF to device
  static Future<String?> savePDFToDevice(Uint8List pdfBytes, String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(pdfBytes);
      return file.path;
    } catch (e) {
      print('Error saving PDF: $e');
      return null;
    }
  }

  // Method to share PDF
  static Future<void> sharePDF(Uint8List pdfBytes, String fileName) async {
    await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
  }

  // Method to print PDF
  static Future<void> printPDF(Uint8List pdfBytes) async {
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdfBytes);
  }

  // Method to save and open PDF (saves to device then shares for opening)
  static Future<String?> saveAndOpenPDF(Uint8List pdfBytes, String fileName) async {
    try {
      // First save the PDF to device
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(pdfBytes);
      
      // Then share/open the PDF using the printing package
      // This will show options to open the PDF in available apps      await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
      
      return file.path;
    } catch (e) {
      print('Error saving and opening PDF: $e');
      return null;
    }
  }

  // Method to generate PDF bytes without immediate action
  static Future<Uint8List> generateMedicationReportBytes() async {
    try {
      // Get patient information
      final prefs = await SharedPreferences.getInstance();
      final patientName = prefs.getString('username') ?? 'Patient';
      final patientId = prefs.getString('patient_id') ?? 'P001';
      final doctorName = prefs.getString('doctor_name') ?? 'Dr. Smith';
      
      // Get all logs
      final logs = await MedicationLogService.getMedicationLogs();
      final stats = await MedicationLogService.getActionStats();
      
      // Use the existing generateMedicationReport method
      return await generateMedicationReport(
        logs: logs,
        stats: stats,
        patientName: patientName,
        patientId: patientId,
        doctorName: doctorName,
      );
    } catch (e) {
      print('Error generating PDF bytes: $e');
      throw Exception('Failed to generate PDF: $e');
    }
  }

  // Method to preview PDF using printing layout
  static Future<void> previewPDF(Uint8List pdfBytes) async {
    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'Medication Report Preview',
      );
    } catch (e) {
      print('Error previewing PDF: $e');
      throw Exception('Failed to preview PDF: $e');
    }
  }
}
