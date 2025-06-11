import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:frontend/services/medication_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Global constants for action IDs
const String medTakenActionId = 'med_taken_action';
const String medForgotActionId = 'med_forgot_action';

// Background notification response handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> onDidReceiveNotificationResponse(NotificationResponse response) async {
  // CRITICAL: Initialize Flutter binding for background context
  WidgetsFlutterBinding.ensureInitialized();
  
  print('🔔 Notification response received: ${response.actionId}');
  print('🔔 Payload: ${response.payload}');
    // CRITICAL: Force SharedPreferences to use the same context as main app
  await _ensureSharedContext();
  
  if (response.payload == null || response.payload!.isEmpty) {
    print('❌ No payload found in notification');
    return;
  }
  
  try {
    Map<String, dynamic> payload = jsonDecode(response.payload!);
    String medicineName = payload['medicine'] ?? 'Unknown Medicine';
    String reminderTimeStr = payload['scheduled_time'] ?? DateTime.now().toIso8601String();
    DateTime reminderTime = DateTime.parse(reminderTimeStr);
    
    print('🔔 Medicine: $medicineName, Time: $reminderTime');
    
    // CRITICAL: Initialize MedicationLogService to use same context
    await MedicationLogService.initialize();
    
    if (response.actionId == medTakenActionId) {
      print('✅ Logging TAKEN action');
      await MedicationLogService.logMedicationAction(
        action: 'taken',
        medicineName: medicineName,
        reminderTime: reminderTime,
        actionTime: DateTime.now(),
      );
      print('✅ TAKEN action logged successfully');
    } else if (response.actionId == medForgotActionId) {
      print('❌ Logging FORGOT action');
      await MedicationLogService.logMedicationAction(
        action: 'forgot',
        medicineName: medicineName,
        reminderTime: reminderTime,
        actionTime: DateTime.now(),
      );
      print('❌ FORGOT action logged successfully');
    }
    
    // Verify the log was stored and can be retrieved
    final logs = await MedicationLogService.getMedicationLogs();
    print('🔔 VERIFICATION: ${logs.length} total logs now stored');
    
  } catch (e) {
    print('❌ Error handling notification response: $e');
  }
}

// Ensure notification context uses same SharedPreferences as main app
Future<void> _ensureSharedContext() async {
  try {
    // Force initialization of SharedPreferences in notification context
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    print('🔔 NOTIFICATION CONTEXT KEYS: $allKeys');
    
    // Check if we can see the UI context keys (username, password)
    if (allKeys.contains('username') && allKeys.contains('password')) {
      print('✅ SUCCESS: Notification context matches UI context');
    } else {
      print('⚠️ WARNING: Notification context differs from UI context');
      print('🔔 Available keys: $allKeys');
      
      // Try to create a sync marker that UI can check
      await prefs.setString('notification_context_active', DateTime.now().toIso8601String());
      print('🔔 Set notification context marker');
    }
    
    // Check if medication_logs key exists in this context
    final medLogs = prefs.getString('medication_logs');
    if (medLogs != null) {
      print('✅ MEDICATION LOGS FOUND in notification context: ${medLogs.length} chars');
    } else {
      print('❌ NO MEDICATION LOGS in notification context - will create new storage');
    }
  } catch (e) {
    print('❌ Context check failed: $e');
  }
}

class NotiService {
  final notificationsPlugin = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<void> initNotification() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();
    final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(currentTimeZone));

    // Request notification permission
    final status = await Permission.notification.request();
    if (status.isDenied) {
      return;
    }
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    // Initialize notification channels with actions
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'daily_medicine_reminder',
      'Daily Medicine Reminder',
      description: 'Daily Medicine Reminder',
      importance: Importance.max,
      playSound: true,
    );

    await notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Initialize with action handling
    const initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    var initSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: [          DarwinNotificationCategory(
          'med_reminder_category',
          actions: [
            DarwinNotificationAction.plain(
              medTakenActionId,
              'TAKEN',
              options: {
                DarwinNotificationActionOption.foreground,
              },
            ),
            DarwinNotificationAction.plain(
              medForgotActionId,
              'MISSED',
              options: {
                DarwinNotificationActionOption.foreground,
              },
            ),
          ],
        )
      ],
    );

    var initSettings = InitializationSettings(
      android: initSettingsAndroid,
      iOS: initSettingsIOS,
    );    await notificationsPlugin.initialize(
      initSettings,      
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );

    _isInitialized = true;
  }
  NotificationDetails _notificationDetails() {    // Android actions
    const AndroidNotificationAction medTakenAction = AndroidNotificationAction(
      medTakenActionId,
      'TAKEN',
      cancelNotification: true, // This will dismiss the notification when tapped
      // titleColor: Color.fromARGB(255, 76, 175, 80), // Green text color
      // contextual: true,
    );

    const AndroidNotificationAction medForgotAction = AndroidNotificationAction(
      medForgotActionId,
      'MISSED',
      cancelNotification: true, // This will dismiss the notification when tapped
      // titleColor: Color.fromARGB(255, 244, 67, 54), // Red text color
      // contextual: true,
    );// Android details
    const androidDetails = AndroidNotificationDetails(
      "daily_medicine_reminder",
      "Daily Medicine Reminder",
      channelDescription: "Daily Medicine Reminder",
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('notification_sound'),
      playSound: true,
      ongoing: true, // Makes notification persistent
      autoCancel: false, // Notification won't auto dismiss
      actions: [medTakenAction, medForgotAction], // Add action buttons
      color: Color.fromARGB(255, 76, 175, 80), // Green color for positive action indication
    );

    // iOS details
    const iosDetails = DarwinNotificationDetails(
      sound: 'notification_sound.wav',
      presentSound: true,
      presentAlert: true,
      presentBadge: true,
      categoryIdentifier: 'med_reminder_category',
    );

    return const NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
  }

  Future<void> showNotification({
    int id = 0,
    String? title,
    String? body,
    String? payload,
  }) async {
    await notificationsPlugin.show(
      id,
      title,
      body,
      _notificationDetails(),
      payload: payload,
    );
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    try {
      if (!_isInitialized) await initNotification();
      final medName = body.replaceFirst('Time to take ', '');
      final id = '${medName}_${hour}_$minute'.hashCode;

      final scheduledDate = _nextInstanceOfTime(hour, minute);

      debugPrint("""
        Scheduling notification:
        - Now: ${tz.TZDateTime.now(tz.local)}
        - Scheduled: $scheduledDate
        - Timezone: ${tz.local.name}
        """);

      await notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        _notificationDetails(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: jsonEncode({
          'medicine': medName,
          'hour': hour,
          'minute': minute,
          'scheduled_time': scheduledDate.toIso8601String(),
        }),
      );
      debugPrint("Notification scheduled successfully for $hour:$minute");
    } catch (e) {
      debugPrint("Error scheduling notification: $e");
      rethrow;
    }
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    return scheduledDate;
  }

  Future<void> cancelNotification(int id) async {
    await notificationsPlugin.cancelAll();
  }

  Future<List<PendingNotificationRequest>> getScheduledNotifications() async {
    return await notificationsPlugin.pendingNotificationRequests();
  }

  Future<List<TimeOfDay>> getScheduledTimesForMedicine(
      String medicineName) async {
    final notifications = await getScheduledNotifications();
    final medicineTimes = <TimeOfDay>[];

    for (var notification in notifications) {
      if (notification.body?.contains(medicineName) ?? false) {
        try {
          // Parse payload if it exists
          final payload = notification.payload != null
              ? jsonDecode(notification.payload!)
              : null;

          if (payload != null && payload is Map<String, dynamic>) {
            medicineTimes.add(TimeOfDay(
              hour: payload['hour'] ?? 0,
              minute: payload['minute'] ?? 0,
            ));
          }
        } catch (e) {
          print('Error parsing notification payload: $e');
        }
      }
    }
    return medicineTimes;
  }

  Future<List<Map<String, dynamic>>> getScheduledReminders(
      String medicineName) async {
    final notifications =
        await notificationsPlugin.pendingNotificationRequests();
    final reminders = <Map<String, dynamic>>[];

    for (final notification in notifications) {
      try {
        if (notification.payload != null) {
          final payload =
              jsonDecode(notification.payload!) as Map<String, dynamic>;
          if (payload['medicine'] == medicineName) {
            reminders.add({
              'id': notification.id,
              'hour': payload['hour'],
              'minute': payload['minute'],
            });
          }
        }
      } catch (e) {
        print('Error parsing notification payload: $e');
      }
    }
    return reminders;
  }

  Future<List<Map<String, dynamic>>> getAllRemindersForToday() async {
    final now = tz.TZDateTime.now(tz.local);
    final notifications =
        await notificationsPlugin.pendingNotificationRequests();
    final todayReminders = <Map<String, dynamic>>[];

    for (final notification in notifications) {
      try {
        if (notification.payload != null) {
          final payload =
              jsonDecode(notification.payload!) as Map<String, dynamic>;
          final hour = payload['hour'] as int;
          final minute = payload['minute'] as int;
          final medicine = payload['medicine'] as String;

          // Create a TZDateTime for today at the scheduled time
          final scheduledTime = tz.TZDateTime(
            tz.local,
            now.year,
            now.month,
            now.day,
            hour,
            minute,
          );

          todayReminders.add({
            'id': notification.id,
            'medicine': medicine,
            'hour': hour,
            'minute': minute,
            'time': TimeOfDay(hour: hour, minute: minute),
            'scheduledTime': scheduledTime,
            'isPast': scheduledTime.isBefore(now),
          });
        }
      } catch (e) {
        debugPrint('Error parsing notification payload: $e');
      }
    }

    // Sort by time (earliest first)
    todayReminders.sort((a, b) {
      final aTime = a['scheduledTime'] as tz.TZDateTime;
      final bTime = b['scheduledTime'] as tz.TZDateTime;
      return aTime.compareTo(bTime);
    });

    return todayReminders;
  }

  Future<List<Map<String, dynamic>>> getRemainingRemindersForToday() async {
    final now = tz.TZDateTime.now(tz.local);
    final allReminders = await getAllRemindersForToday();

    // Filter to only include reminders that are today and not in the past
    return allReminders.where((reminder) {
      final scheduledTime = reminder['scheduledTime'] as tz.TZDateTime;
      // Include if it's either in the future or within the last 30 minutes
      return scheduledTime.isAfter(now.subtract(const Duration(minutes: 30)));
    }).toList();
  }

  // Test method to create a notification and test the actions
  Future<void> testNotificationActions() async {
    if (!_isInitialized) await initNotification();
    
    try {
      final now = DateTime.now();
      final testTime = now.add(const Duration(seconds: 5));
      
      await notificationsPlugin.show(
        999, // Test notification ID
        'TEST NOTIFICATION',
        'Tap the buttons to test logging - Test Medicine',
        _notificationDetails(),
        payload: jsonEncode({
          'medicine': 'Test Medicine',
          'scheduled_time': testTime.toIso8601String(),
        }),
      );
      
      print('🧪 Test notification created - tap the action buttons to test logging');
    } catch (e) {
      print('❌ Error creating test notification: $e');
    }
  }

  // Test method to manually trigger notification response handler
  Future<void> testContextSynchronization() async {
    print('🧪 Testing context synchronization manually...');
    
    try {
      // Create a mock notification response
      final testPayload = jsonEncode({
        'medicine': 'Context Test Medicine',
        'scheduled_time': DateTime.now().toIso8601String(),
      });
      
      // Simulate the notification response
      final mockResponse = NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        actionId: medTakenActionId,
        payload: testPayload,
      );
      
      print('🧪 Manually calling notification response handler...');
      await onDidReceiveNotificationResponse(mockResponse);
      
      print('✅ Context synchronization test completed');
    } catch (e) {
      print('❌ Error in context synchronization test: $e');
    }
  }
}
