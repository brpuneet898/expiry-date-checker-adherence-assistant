import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class MedicationLogService {
  static const String _logKey = 'medication_logs';
  static const String _logFileName = 'medication_logs.json';
  static SharedPreferences? _prefs;
  static bool _isInitialized = false;
  
  // Force SharedPreferences to use the exact same instance across all contexts
  static Future<void> _initPrefs() async {
    if (_prefs == null || !_isInitialized) {
      print('🔄 Initializing SharedPreferences...');
      
      // Force a fresh instance to ensure we get the latest context
      _prefs = await SharedPreferences.getInstance();
      _isInitialized = true;
      
      // Verify initialization by checking available keys
      final allKeys = _prefs!.getKeys();
      print('📱 SharedPreferences initialized with keys: $allKeys');
      
      // Check if this is the same context as UI (should have username/password)
      if (allKeys.contains('username') || allKeys.contains('password')) {
        print('✅ Using MAIN UI SharedPreferences context');
      } else {
        print('⚠️ Using different SharedPreferences context - may cause isolation issues');
        
        // Try to establish context connection by setting a marker
        await _prefs!.setString('medication_service_active', DateTime.now().toIso8601String());
        print('🔧 Set medication service marker to establish context');
      }
    }
  }
  
  // FORCE SharedPreferences synchronization across contexts
  static Future<void> _forceSyncContext() async {
    if (_prefs != null) {
      // Force a reload by nulling and reinitializing
      _prefs = null;
      _isInitialized = false;
      await _initPrefs();
    }
  }
  
  // Getter to ensure prefs is always available and synchronized
  static Future<SharedPreferences> get prefs async {
    await _initPrefs();
    return _prefs!;
  }
  
  // File-based storage as backup for cross-context access
  static Future<File> get _logFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_logFileName');
  }    static Future<void> logMedicationAction({
    required String action, // 'taken' or 'forgot'
    required String medicineName,
    required DateTime reminderTime,
    required DateTime actionTime,
  }) async {
    print('🔄 Logging medication action: $action for $medicineName');
    
    try {
      // CRITICAL: Force context synchronization before logging
      await _forceSyncContext();
      
      // Create log entry
      Map<String, dynamic> newLog = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'action': action,
        'medicineName': medicineName,
        'reminderTime': reminderTime.toIso8601String(),
        'actionTime': actionTime.toIso8601String(),
      };
      
      // Use both SharedPreferences and file storage for reliability
      await _storeLogBoth(newLog);
      
      print('✅ Successfully logged $action action for $medicineName');
    } catch (e) {
      print('❌ Failed to log medication action: $e');
    }
  }
  
  // Store log in both SharedPreferences and file for cross-context access
  static Future<void> _storeLogBoth(Map<String, dynamic> newLog) async {
    // Get existing logs from both sources
    List<Map<String, dynamic>> existingLogs = await _getLogsFromBothSources();
    
    // Add new log
    existingLogs.add(newLog);
    
    // Store in SharedPreferences
    try {
      final preferences = await prefs;
      await preferences.setString(_logKey, jsonEncode(existingLogs));
      print('✅ Stored in SharedPreferences: ${existingLogs.length} logs');
    } catch (e) {
      print('❌ Failed to store in SharedPreferences: $e');
    }
    
    // Store in file as backup
    try {
      final file = await _logFile;
      await file.writeAsString(jsonEncode(existingLogs));
      print('✅ Stored in file: ${existingLogs.length} logs');
    } catch (e) {
      print('❌ Failed to store in file: $e');
    }
  }
  
  // Get logs from both sources and merge
  static Future<List<Map<String, dynamic>>> _getLogsFromBothSources() async {
    List<Map<String, dynamic>> sharedPrefsLogs = [];
    List<Map<String, dynamic>> fileLogs = [];
    
    // Try SharedPreferences first
    try {
      final preferences = await prefs;
      final logsJson = preferences.getString(_logKey);
      if (logsJson != null && logsJson.isNotEmpty) {
        final List<dynamic> logsList = jsonDecode(logsJson);
        sharedPrefsLogs = logsList.cast<Map<String, dynamic>>();
        print('📱 Found ${sharedPrefsLogs.length} logs in SharedPreferences');
      }
    } catch (e) {
      print('❌ Error reading from SharedPreferences: $e');
    }
    
    // Try file storage as backup
    try {
      final file = await _logFile;
      if (await file.exists()) {
        final fileContent = await file.readAsString();
        if (fileContent.isNotEmpty) {
          final List<dynamic> logsList = jsonDecode(fileContent);
          fileLogs = logsList.cast<Map<String, dynamic>>();
          print('📁 Found ${fileLogs.length} logs in file');
        }
      }
    } catch (e) {
      print('❌ Error reading from file: $e');
    }
    
    // Merge and deduplicate logs by ID
    Map<String, Map<String, dynamic>> mergedLogs = {};
    
    // Add SharedPreferences logs
    for (var log in sharedPrefsLogs) {
      mergedLogs[log['id']] = log;
    }
    
    // Add file logs (newer ones will overwrite)
    for (var log in fileLogs) {
      mergedLogs[log['id']] = log;
    }
    
    List<Map<String, dynamic>> result = mergedLogs.values.toList();
    
    // Sort by action time (newest first)
    result.sort((a, b) => 
      DateTime.parse(b['actionTime']).compareTo(DateTime.parse(a['actionTime']))
    );
    
    print('🔄 Merged logs: ${result.length} total');
    return result;
  }
  static Future<List<Map<String, dynamic>>> getMedicationLogs() async {
    print('🔍 Getting medication logs...');
    
    // Always try both sources for maximum reliability
    List<Map<String, dynamic>> logs = await _getLogsFromBothSources();
    
    if (logs.isNotEmpty) {
      print('✅ Retrieved ${logs.length} logs successfully');
      // Sort by action time (newest first)
      logs.sort((a, b) => 
        DateTime.parse(b['actionTime']).compareTo(DateTime.parse(a['actionTime']))
      );
    } else {
      print('❌ No logs found in either storage method');
    }
    
    return logs;
  }
  
  static Future<List<Map<String, dynamic>>> getLogsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final allLogs = await getMedicationLogs();
    
    return allLogs.where((log) {
      final actionTime = DateTime.parse(log['actionTime']);
      return actionTime.isAfter(startDate) && actionTime.isBefore(endDate);
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> getLogsByMedicine(String medicineName) async {
    final allLogs = await getMedicationLogs();
    
    return allLogs.where((log) => 
      log['medicineName'].toString().toLowerCase() == medicineName.toLowerCase()
    ).toList();
  }

  static Future<List<Map<String, dynamic>>> getLogsByAction(String action) async {
    final allLogs = await getMedicationLogs();
    
    return allLogs.where((log) => log['action'] == action).toList();
  }

  static Future<void> clearAllLogs() async {
    final preferences = await prefs; // Use cached instance
    await preferences.remove(_logKey);
    print('🗑️ All logs cleared');
  }
  
  static Future<Map<String, int>> getActionStats() async {
    List<Map<String, dynamic>> logs = await getMedicationLogs();
    
    int taken = logs.where((log) => log['action'] == 'taken').length;
    int forgot = logs.where((log) => log['action'] == 'forgot').length;
    
    return {
      'taken': taken,
      'forgot': forgot,
      'total': logs.length,
    };
  }
  
  // Add this debug method to check what's actually stored
  static Future<void> debugStorage() async {
    final preferences = await prefs; // Use cached instance
    
    // Check all keys
    Set<String> allKeys = preferences.getKeys();
    print('🔍 All SharedPreferences keys: $allKeys');
    
    // FIX: Use getString instead of getStringList
    String? logsJson = preferences.getString('medication_logs');
    print('🔍 medication_logs raw JSON: $logsJson');
    
    if (logsJson != null) {
      try {
        List<dynamic> logsList = jsonDecode(logsJson);
        print('🔍 Parsed logs count: ${logsList.length}');
        print('🔍 Parsed logs: $logsList');
      } catch (e) {
        print('❌ Error parsing stored JSON: $e');
      }
    }
    
    // Test getMedicationLogs method
    List<Map<String, dynamic>> retrievedLogs = await getMedicationLogs();
    print('🔍 getMedicationLogs() returned: ${retrievedLogs.length} logs');
  }

  static Future<void> debugAllStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    
    print('🔍 ALL STORAGE KEYS: $allKeys');
    
    // Check for different possible keys
    final variations = [
      'medication_logs',
      'medicationLogs', 
      'logs',
      'med_logs',
      'notification_logs'
    ];
    
    for (String key in variations) {
      final value = prefs.getString(key);
      if (value != null) {
        print('🔍 KEY "$key" HAS DATA: ${value.length} chars');
        print('🔍 FIRST 100 CHARS: ${value.substring(0, min(100, value.length))}');
      }
    }
  }
    // Initialize the service early in your app with context verification
  static Future<void> initialize() async {
    print('🔄 Initializing MedicationLogService...');
    await _initPrefs();
    
    // Verify we can access the same context as the main app
    final preferences = await prefs;
    final allKeys = preferences.getKeys();
    print('🔧 Available SharedPreferences keys: $allKeys');
    
    // Test storage capability
    const testKey = 'test_medication_service';
    const testValue = 'service_initialized';
    await preferences.setString(testKey, testValue);
    
    final readValue = preferences.getString(testKey);
    if (readValue == testValue) {
      print('✅ MedicationLogService storage test PASSED');
      // Clean up test data
      await preferences.remove(testKey);
    } else {
      print('❌ MedicationLogService storage test FAILED');
    }
    
    print('✅ MedicationLogService initialized successfully');
  }
}
