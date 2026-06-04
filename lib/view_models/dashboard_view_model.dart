import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:unitransit_admin/core/services/firebase_service.dart';
import 'package:unitransit_admin/models/notification_model.dart';
import 'package:unitransit_admin/models/support_ticket_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardViewModel extends ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService();
  bool _isLoading = false;
  int _selectedIndex = 0;
  String _searchQuery = '';
  String _selectedGender = 'All';
  String _selectedTimeScale = 'Week'; // Day, Week, Month, Year

  List<SystemNotificationModel> _notifications = [];
  final Set<String> _dismissedNotificationIds = {};
  StreamSubscription<List<SupportTicketModel>>? _ticketSubscription;

  bool get isLoading => _isLoading;
  int get selectedIndex => _selectedIndex;
  String get searchQuery => _searchQuery;
  String get selectedGender => _selectedGender;
  String get selectedTimeScale => _selectedTimeScale;
  List<SystemNotificationModel> get notifications => _notifications;
  int get unreadNotificationsCount =>
      _notifications.where((n) => !n.isRead).length;

  void setSelectedIndex(int index) {
    _selectedIndex = index;
    notifyListeners();
  }

  void resetToDashboard() {
    _selectedIndex = 0;
    notifyListeners();
  }

  void setTimeScale(String scale) {
    _selectedTimeScale = scale;
    notifyListeners();
  }

  void updateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setSelectedGender(String gender) {
    _selectedGender = gender;
    notifyListeners();
  }

  // Real data stats
  int totalStudents = 0;
  int totalDrivers = 0;
  int totalAdmins = 0; // Added for Super Admin dashboard
  int activeTrips = 42;

  int? _parseTimestamp(dynamic val, [String? tripId]) {
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) {
      return int.tryParse(val);
    }
    if (tripId != null) {
      return int.tryParse(tripId);
    }
    return null;
  }
  int pendingAlerts = 0;
  double totalRevenue = 12450.0;

  int activeEmergencyAlerts = 0;
  List<Map<String, dynamic>> _emergencyAlerts = [];
  List<Map<String, dynamic>> get emergencyAlerts => _emergencyAlerts;
  StreamSubscription? _emergencySubscription;

  StreamSubscription? _statsSubscription;

  // Live Trip Alerts
  StreamSubscription? _tripAlertsSubscription;
  final StreamController<Map<String, dynamic>> _newTripAlertController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onNewTripAlert =>
      _newTripAlertController.stream;

  List<Map<String, dynamic>> _allTrips = [];
  List<SupportTicketModel> _allTickets = [];
  List<Map<String, dynamic>> _recentActivities = [];
  StreamSubscription? _tripHistorySubscription;

  List<Map<String, dynamic>> get recentActivities => _recentActivities;
  List<double> get weeklyTripStats => _getTripStats();

  DashboardViewModel() {
    _loadDismissedNotifications();
    _listenToStats();
    _listenToNewTickets();
    _listenToEmergencyAlerts();
    _listenToTripAlerts();
    _listenToTripHistory();
  }

  Future<void> _loadDismissedNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('dismissed_notification_ids') ?? [];
      _dismissedNotificationIds.addAll(list);
      _updateSystemNotifications();
    } catch (e) {
      debugPrint("Error loading dismissed notifications: $e");
    }
  }

  Future<void> _saveDismissedNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'dismissed_notification_ids',
        _dismissedNotificationIds.toList(),
      );
    } catch (e) {
      debugPrint("Error saving dismissed notifications: $e");
    }
  }

  void _listenToTripHistory() {
    _tripHistorySubscription?.cancel();
    _tripHistorySubscription = _firebaseService.getTripHistoryStream().listen((
      trips,
    ) {
      _allTrips = trips;
      _updateRecentActivities();
    });
  }

  void _listenToTripAlerts() {
    _tripAlertsSubscription?.cancel();
    final appStartTime = DateTime.now().millisecondsSinceEpoch;
    _tripAlertsSubscription = _firebaseService.getTripAlertsStream().listen((
      alert,
    ) {
      final timestamp = alert['timestamp'] ?? 0;
      // Only notify for alerts generated after the app starts
      if (timestamp >= appStartTime) {
        _newTripAlertController.add(alert);
      }
    });
  }

  void _listenToEmergencyAlerts() {
    _emergencySubscription?.cancel();
    _emergencySubscription = _firebaseService.getEmergencyAlerts().listen((
      alerts,
    ) {
      _emergencyAlerts = alerts;
      activeEmergencyAlerts =
          alerts.where((a) => a['status'] == 'active').length;
      _updateRecentActivities();
      _updateSystemNotifications();
    });
  }

  Future<void> resolveEmergencyAlert(
    String id, {
    String? notes,
    String? resolvedBy,
  }) async {
    try {
      await _firebaseService.resolveEmergencyAlert(
        id,
        notes: notes,
        resolvedBy: resolvedBy,
      );
    } catch (e) {
      debugPrint("Error resolving emergency alert: $e");
    }
  }

  void _listenToNewTickets() {
    _ticketSubscription?.cancel();
    _ticketSubscription = _firebaseService.getTickets().listen((tickets) {
      _allTickets = tickets;
      final pendingTickets =
          tickets.where((t) => t.status.toLowerCase() == 'pending').toList();
      pendingAlerts = pendingTickets.length;

      _updateRecentActivities();
      _updateSystemNotifications();
    });
  }

  void _listenToStats() {
    _statsSubscription?.cancel();

    // Truly Real-time Stats: Listen to multiple sources
    _firebaseService.getRealTimeStats().listen((stats) {
      totalDrivers = stats['totalDrivers'] ?? 0;
      totalStudents = stats['totalStudents'] ?? 0;
      activeTrips = stats['activeTrips'] ?? 0;
      totalRevenue = (stats['totalRevenue'] ?? 0.0).toDouble();
      notifyListeners();
    });

    // Separately monitor admins for instant dashboard update
    FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'Admin')
        .snapshots()
        .listen((snap) {
          totalAdmins = snap.docs.length;
          notifyListeners();
        });
  }

  void _updateRecentActivities() {
    final List<Map<String, dynamic>> activities = [];

    // 1. Add Trips
    for (var trip in _allTrips) {
      final status = trip['status'] ?? 'active';
      final busNumber = trip['busNumber'] ?? 'N/A';
      final from = trip['from'] ?? 'Unknown';
      final to = trip['to'] ?? 'Unknown';
      final parsedStartTime = _parseTimestamp(trip['startTime'], trip['tripId']);

      if (parsedStartTime != null) {
        final timestamp = DateTime.fromMillisecondsSinceEpoch(parsedStartTime);
        if (status == 'active') {
          activities.add({
            'title': 'Bus #$busNumber started route',
            'subtitle': '$from ➔ $to',
            'timestamp': timestamp,
            'icon': Icons.directions_bus_rounded,
            'color': Colors.blue,
          });
        } else {
          final parsedEndTime = _parseTimestamp(trip['endTime']) ?? parsedStartTime;
          final endTimestamp = DateTime.fromMillisecondsSinceEpoch(parsedEndTime);
          activities.add({
            'title': 'Bus #$busNumber arrived',
            'subtitle': 'Completed route: $from ➔ $to',
            'timestamp': endTimestamp,
            'icon': Icons.check_circle_rounded,
            'color': Colors.green,
          });
        }
      }
    }

    // 2. Add Support Tickets
    for (var ticket in _allTickets) {
      activities.add({
        'title': 'Support Ticket: ${ticket.name}',
        'subtitle': ticket.issue,
        'timestamp': ticket.timestamp,
        'icon': Icons.support_agent_rounded,
        'color':
            ticket.status.toLowerCase() == 'pending'
                ? Colors.orange
                : Colors.purple,
      });
    }

    // 3. Add Emergency Alerts
    for (var alert in _emergencyAlerts) {
      final status = alert['status'] ?? 'active';
      final message = alert['message'] ?? 'Emergency SOS Alert';
      final timeVal = alert['timestamp'];
      final parsedAlertTime = _parseTimestamp(timeVal);

      if (parsedAlertTime != null) {
        final timestamp = DateTime.fromMillisecondsSinceEpoch(parsedAlertTime);
        if (status == 'active') {
          activities.add({
            'title': '🚨 SOS Alert Active!',
            'subtitle': message,
            'timestamp': timestamp,
            'icon': Icons.warning_rounded,
            'color': Colors.red,
          });
        } else {
          final resolvedAtVal = alert['resolvedAt'];
          final parsedResolvedTime = _parseTimestamp(resolvedAtVal) ?? parsedAlertTime;
          final resolvedTimestamp = DateTime.fromMillisecondsSinceEpoch(parsedResolvedTime);
          activities.add({
            'title': '🟢 SOS Alert Resolved',
            'subtitle': 'Notes: ${alert['resolutionNotes'] ?? ''}',
            'timestamp': resolvedTimestamp,
            'icon': Icons.crisis_alert_rounded,
            'color': Colors.green,
          });
        }
      }
    }

    // Sort all activities by timestamp descending
    activities.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

    // Take only the top 10 activities
    _recentActivities = activities.take(10).toList();
    notifyListeners();
  }

  void _updateSystemNotifications() {
    final List<SystemNotificationModel> logs = [];

    // 1. Pending Support Tickets (both read and unread)
    final pendingTickets = _allTickets.where(
      (t) => t.status.toLowerCase() == 'pending',
    );
    for (var t in pendingTickets) {
      final bool isRead =
          t.adminRead || _dismissedNotificationIds.contains(t.id);
      logs.add(
        SystemNotificationModel(
          id: t.id,
          title: 'New Support Request',
          message: '${t.name}: ${t.issue}',
          timestamp: t.timestamp,
          type: NotificationType.support,
          isRead: isRead,
          color: Colors.orange,
        ),
      );
    }

    // 2. Active SOS / Emergency Alerts (both read and unread)
    final activeSOS = _emergencyAlerts.where((a) => a['status'] == 'active');
    for (var a in activeSOS) {
      final String alertId = a['id'] ?? '';
      final timeVal = a['timestamp'];
      final parsedAlertTime = _parseTimestamp(timeVal);
      final timestamp =
          parsedAlertTime != null
              ? DateTime.fromMillisecondsSinceEpoch(parsedAlertTime)
              : DateTime.now();
      final bool isRead =
          (a['adminRead'] == true) ||
          _dismissedNotificationIds.contains(alertId);
      logs.add(
        SystemNotificationModel(
          id: alertId,
          title: 'Active SOS Alert!',
          message:
              'Driver: ${a['driverName'] ?? 'Unknown'} (Bus #${a['busNumber'] ?? 'N/A'}) - ${a['message'] ?? 'Emergency SOS'}',
          timestamp: timestamp,
          type: NotificationType.warning,
          isRead: isRead,
          color: Colors.red,
        ),
      );
    }

    // Sort by timestamp descending
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    _notifications = logs;
    notifyListeners();
  }

  void dismissNotification(String id) {
    _dismissedNotificationIds.add(id);
    _saveDismissedNotifications();
    _updateSystemNotifications();

    // Persist to Firebase as read in background
    _firebaseService.markTicketAsRead(id).catchError((e) {
      debugPrint("Error updating ticket adminRead: $e");
    });
    _firebaseService.markEmergencyAlertAsRead(id).catchError((e) {
      debugPrint("Error updating emergency alert adminRead: $e");
    });
  }

  void clearAllNotifications() {
    final listToDismiss = List<SystemNotificationModel>.from(_notifications);
    for (var notif in listToDismiss) {
      _dismissedNotificationIds.add(notif.id);
      if (notif.type == NotificationType.support) {
        _firebaseService.markTicketAsRead(notif.id).catchError((e) {
          debugPrint("Error updating ticket adminRead: $e");
        });
      } else if (notif.type == NotificationType.warning) {
        _firebaseService.markEmergencyAlertAsRead(notif.id).catchError((e) {
          debugPrint("Error updating emergency alert adminRead: $e");
        });
      }
    }
    _saveDismissedNotifications();
    _updateSystemNotifications();
  }

  List<double> _getTripStats() {
    final now = DateTime.now();

    if (_selectedTimeScale == 'Day') {
      final List<double> hourly = List.filled(24, 0.0);
      final startOfDay = DateTime(now.year, now.month, now.day);
      for (var trip in _allTrips) {
        final startTimeVal = trip['startTime'];
        final parsedTime = _parseTimestamp(startTimeVal, trip['tripId']);
        if (parsedTime == null) continue;
        final tripDate = DateTime.fromMillisecondsSinceEpoch(parsedTime);
        if (tripDate.year == now.year &&
            tripDate.month == now.month &&
            tripDate.day == now.day) {
          hourly[tripDate.hour] += 1.0;
        }
      }
      return hourly;
    } else if (_selectedTimeScale == 'Month') {
      // Show stats for the last 30 days
      final List<double> daily = List.filled(30, 0.0);
      for (var trip in _allTrips) {
        final startTimeVal = trip['startTime'];
        final parsedTime = _parseTimestamp(startTimeVal, trip['tripId']);
        if (parsedTime == null) continue;
        final tripDate = DateTime.fromMillisecondsSinceEpoch(parsedTime);
        final diff = now.difference(tripDate).inDays;
        if (diff >= 0 && diff < 30) {
          daily[29 - diff] += 1.0;
        }
      }
      return daily;
    } else if (_selectedTimeScale == 'Year') {
      final List<double> monthly = List.filled(12, 0.0);
      for (var trip in _allTrips) {
        final startTimeVal = trip['startTime'];
        final parsedTime = _parseTimestamp(startTimeVal, trip['tripId']);
        if (parsedTime == null) continue;
        final tripDate = DateTime.fromMillisecondsSinceEpoch(parsedTime);
        if (tripDate.year == now.year) {
          monthly[tripDate.month - 1] += 1.0;
        }
      }
      return monthly;
    } else {
      // Default to Week
      final List<double> counts = List.filled(7, 0.0);
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final startOfWeek = DateTime(monday.year, monday.month, monday.day);
      final endOfWeek = startOfWeek.add(const Duration(days: 7));

      for (var trip in _allTrips) {
        final startTimeVal = trip['startTime'];
        final parsedTime = _parseTimestamp(startTimeVal, trip['tripId']);
        if (parsedTime == null) continue;
        final tripDate = DateTime.fromMillisecondsSinceEpoch(parsedTime);

        if ((tripDate.isAfter(startOfWeek) ||
                tripDate.isAtSameMomentAs(startOfWeek)) &&
            tripDate.isBefore(endOfWeek)) {
          final dayIndex = tripDate.weekday - 1;
          if (dayIndex >= 0 && dayIndex < 7) counts[dayIndex] += 1.0;
        }
      }
      return counts;
    }
  }

  @Deprecated('Use _getTripStats instead')
  List<double> _getWeeklyTripStats() {
    return _getTripStats();
  }

  Future<void> refreshData() async {
    _listenToStats();
    _listenToNewTickets();
    _listenToEmergencyAlerts();
    _listenToTripHistory();
  }

  @override
  void dispose() {
    _statsSubscription?.cancel();
    _ticketSubscription?.cancel();
    _emergencySubscription?.cancel();
    _tripAlertsSubscription?.cancel();
    _tripHistorySubscription?.cancel();
    _newTripAlertController.close();
    super.dispose();
  }
}
