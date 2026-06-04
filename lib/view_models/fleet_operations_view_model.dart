import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:unitransit_admin/models/bus_schedule_model.dart';

class FleetOperationsViewModel extends ChangeNotifier {
  final DatabaseReference _busesRef = FirebaseDatabase.instance.ref('buses');
  final DatabaseReference _polylinesRef = FirebaseDatabase.instance.ref('custom_polylines');
  StreamSubscription? _busesSubscription;
  StreamSubscription? _schedulesSubscription;
  StreamSubscription? _polylinesSubscription;

  // --- State ---
  List<Map<String, dynamic>> _allBuses = [];
  List<Map<String, dynamic>> _filteredBuses = [];
  List<BusSchedule> _schedules = [];
  Map<String, List<LatLng>> _polylines = {};
  bool _isSuperAdmin = false;

  String? _selectedBusId;
  bool _isLoading = true;

  String _searchQuery = '';
  String _selectedGenderFilter = 'All';
  String _selectedRouteFilter = 'All';
  String _selectedBusNumberFilter = 'All';

  DateTime _selectedDate = DateTime.now();
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);

  final List<String> _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  // --- Getters ---
  List<Map<String, dynamic>> get allBuses => _allBuses;
  List<Map<String, dynamic>> get filteredBuses => _filteredBuses;
  List<BusSchedule> get schedules => _schedules;
  Map<String, List<LatLng>> get polylines => _polylines;
  String? get selectedBusId => _selectedBusId;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  String get selectedGenderFilter => _selectedGenderFilter;
  String get selectedRouteFilter => _selectedRouteFilter;
  String get selectedBusNumberFilter => _selectedBusNumberFilter;
  DateTime get selectedDate => _selectedDate;
  DateTime get currentMonth => _currentMonth;
  int get activeCount => _allBuses.length;
  bool get isSuperAdmin => _isSuperAdmin;

  void setSuperAdmin(bool value) {
    if (_isSuperAdmin != value) {
      _isSuperAdmin = value;
      applyFilters();
    }
  }

  Map<String, dynamic>? get selectedBus {
    if (_selectedBusId == null) return null;
    final match = _filteredBuses.where((b) => b['id'] == _selectedBusId);
    if (match.isEmpty) return null;
    final bus = match.first;
    return bus.isNotEmpty ? bus : null;
  }

  bool get hasActiveFilters =>
      _selectedGenderFilter != 'All' ||
      _selectedRouteFilter != 'All' ||
      _selectedBusNumberFilter != 'All' ||
      _searchQuery.isNotEmpty;

  // --- Initialization ---
  FleetOperationsViewModel() {
    _listenToActiveBuses();
    _listenToSchedules();
    _listenToPolylines();
  }

  void _listenToActiveBuses() {
    _busesSubscription = _busesRef.onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      final List<Map<String, dynamic>> loadedBuses = [];

      if (data != null) {
        data.forEach((key, value) {
          if (value is Map) {
            loadedBuses.add({
              'id': key.toString(),
              ...Map<String, dynamic>.from(value),
            });
          }
        });
      }

      _allBuses = loadedBuses;
      _isLoading = false;
      applyFilters();
    }, onError: (error) {
      debugPrint("Error loading active buses: $error");
      _isLoading = false;
      notifyListeners();
    });
  }

  void _listenToSchedules() {
    _schedulesSubscription = FirebaseFirestore.instance
        .collection('schedules')
        .snapshots()
        .listen((snapshot) {
      _schedules = snapshot.docs
          .map((doc) => BusSchedule.fromMap(doc.id, doc.data()))
          .toList();
      notifyListeners();
    });
  }

  void _listenToPolylines() {
    _polylinesSubscription = _polylinesRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) {
        _polylines = {};
      } else {
        final Map<String, List<LatLng>> loaded = {};
        data.forEach((routeName, coords) {
          if (coords is List) {
            final List<LatLng> path = [];
            for (var c in coords) {
              if (c is Map) {
                final lat = (c['lat'] ?? c['latitude'] ?? 0.0) as num;
                final lng = (c['lng'] ?? c['longitude'] ?? 0.0) as num;
                path.add(LatLng(lat.toDouble(), lng.toDouble()));
              }
            }
            if (path.isNotEmpty) {
              loaded[routeName.toString()] = path;
            }
          }
        });
        _polylines = loaded;
      }
      notifyListeners();
    });
  }

  // --- Filter Actions ---
  void updateSearchQuery(String query) {
    _searchQuery = query;
    applyFilters();
  }

  void setGenderFilter(String gender) {
    _selectedGenderFilter = gender;
    applyFilters();
  }

  void setRouteFilter(String route) {
    _selectedRouteFilter = route;
    applyFilters();
  }

  void setBusNumberFilter(String busNum) {
    _selectedBusNumberFilter = busNum;
    applyFilters();
  }

  void clearAllFilters() {
    _searchQuery = '';
    _selectedGenderFilter = 'All';
    _selectedRouteFilter = 'All';
    _selectedBusNumberFilter = 'All';
    applyFilters();
  }

  void selectBus(String? busId) {
    _selectedBusId = busId;
    notifyListeners();
  }

  bool _isRouteMatching(String busFrom, String busTo, String selectedRouteFilter) {
    if (selectedRouteFilter == 'All') return true;
    
    // Split the selected route filter by common route separators
    final parts = selectedRouteFilter.split(RegExp(r'(➔|->|➔|➔|to)'));
    if (parts.length < 2) return false;
    
    final filterFrom = parts[0].trim().toLowerCase();
    final filterTo = parts[1].trim().toLowerCase();
    
    final bFrom = busFrom.trim().toLowerCase();
    final bTo = busTo.trim().toLowerCase();
    
    // Helper to check if two strings are equivalent (including common abbreviations or spelling errors)
    bool matchPart(String actual, String filter) {
      if (actual == filter) return true;
      if (actual.contains(filter) || filter.contains(actual)) return true;
      
      // Handle Baghdad Campus vs Baghdad
      final normActual = actual.replaceAll('campus', '').trim();
      final normFilter = filter.replaceAll('campus', '').trim();
      if (normActual == normFilter) return true;
      
      // Handle Abbasia vs Abasia spelling difference
      final abbasiaSpelling = ['abbasia', 'abasia', 'old'];
      if (abbasiaSpelling.any((s) => normActual.contains(s)) && 
          abbasiaSpelling.any((s) => normFilter.contains(s))) {
        return true;
      }
      
      return false;
    }
    
    return matchPart(bFrom, filterFrom) && matchPart(bTo, filterTo);
  }

  void applyFilters() {
    List<Map<String, dynamic>> temp = _allBuses;

    // Search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      temp = temp.where((bus) {
        final busNum = (bus['busNumber'] ?? '').toString().toLowerCase();
        final driver = (bus['driverName'] ?? '').toString().toLowerCase();
        final from = (bus['from'] ?? '').toString().toLowerCase();
        final to = (bus['to'] ?? '').toString().toLowerCase();
        final plate = (bus['plateNumber'] ?? '').toString().toLowerCase();
        return busNum.contains(query) ||
            driver.contains(query) ||
            from.contains(query) ||
            to.contains(query) ||
            plate.contains(query);
      }).toList();
    }

    // Gender filter
    if (_selectedGenderFilter != 'All') {
      temp = temp.where((bus) {
        final gender = (bus['gender'] ?? '').toString().toLowerCase().trim();
        return gender == _selectedGenderFilter.toLowerCase().trim();
      }).toList();
    }

    // Route filter
    if (_selectedRouteFilter != 'All') {
      temp = temp.where((bus) {
        final from = (bus['from'] ?? '').toString();
        final to = (bus['to'] ?? '').toString();
        return _isRouteMatching(from, to, _selectedRouteFilter);
      }).toList();
    }

    // Bus number filter
    if (_selectedBusNumberFilter != 'All') {
      temp = temp.where((bus) {
        final busNum = (bus['busNumber'] ?? '').toString().toLowerCase().trim();
        return busNum == _selectedBusNumberFilter.toLowerCase().trim();
      }).toList();
    }

    _filteredBuses = temp;
    notifyListeners();
  }

  // --- Derived Data ---
  List<String> get uniqueRoutes {
    final routes = <String>{};
    // Use defined schedules (official routes)
    for (final schedule in _schedules) {
      if (schedule.from.isNotEmpty && schedule.to.isNotEmpty) {
        routes.add('${schedule.from.trim()} ➔ ${schedule.to.trim()}');
      }
    }
    // Add routes from active buses if they don't fuzzy match any schedule route
    for (final bus in _allBuses) {
      final busFrom = (bus['from'] ?? '').toString().trim();
      final busTo = (bus['to'] ?? '').toString().trim();
      if (busFrom.isNotEmpty && busTo.isNotEmpty) {
        final busRouteLabel = '$busFrom ➔ $busTo';
        
        bool alreadyExists = false;
        for (final r in routes) {
          if (_isRouteMatching(busFrom, busTo, r)) {
            alreadyExists = true;
            break;
          }
        }
        if (!alreadyExists) {
          routes.add(busRouteLabel);
        }
      }
    }
    return ['All', ...routes];
  }

  List<String> get uniqueBusNumbers {
    final numbers = <String>{};
    for (final bus in _allBuses) {
      final busNum = (bus['busNumber'] ?? '').toString();
      if (busNum.isNotEmpty && busNum != 'N/A') {
        numbers.add(busNum);
      }
    }
    final sorted = numbers.toList()..sort((a, b) {
      final aNum = int.tryParse(a) ?? 0;
      final bNum = int.tryParse(b) ?? 0;
      return aNum.compareTo(bNum);
    });
    return ['All', ...sorted];
  }

  // --- Schedule Matching ---
  BusSchedule? getMatchingSchedule(Map<String, dynamic> bus) {
    if (_schedules.isEmpty) return null;
    
    final scheduleId = (bus['scheduleId'] ?? '').toString().trim();
    if (scheduleId.isNotEmpty) {
      final matchedById = _schedules.where((s) => s.id == scheduleId).toList();
      if (matchedById.isNotEmpty) return matchedById.first;
    }

    final busNum = (bus['busNumber'] ?? '').toString().toLowerCase().trim();
    if (busNum.isEmpty) return null;

    final matchedByBus = _schedules.where((s) {
      final sBus = (s.busNumber ?? '').toLowerCase().trim();
      return sBus == busNum || sBus.contains(busNum) || busNum.contains(sBus);
    }).toList();

    if (matchedByBus.isNotEmpty) {
      final selectedWeekday = DateFormat('EEEE').format(_selectedDate);
      final selectedDateStr = _formatDate(_selectedDate);
      for (var schedule in matchedByBus) {
        if (schedule.date == selectedDateStr) return schedule;
      }
      for (var schedule in matchedByBus) {
        if (schedule.operatingDays != null && schedule.operatingDays!.contains(selectedWeekday)) {
          return schedule;
        }
      }
      return matchedByBus.first;
    }

    final matchedByRoute = _schedules.where((s) {
      final sFrom = s.from.toLowerCase().trim();
      final sTo = s.to.toLowerCase().trim();
      final busFrom = (bus['from'] ?? '').toString().toLowerCase().trim();
      final busTo = (bus['to'] ?? '').toString().toLowerCase().trim();
      return sFrom == busFrom && sTo == busTo;
    }).toList();

    if (matchedByRoute.isNotEmpty) {
      final selectedDateStr = _formatDate(_selectedDate);
      for (var schedule in matchedByRoute) {
        if (schedule.date == selectedDateStr) return schedule;
      }
      return matchedByRoute.first;
    }

    return null;
  }

  int get totalSchedulesToday {
    final selectedWeekday = DateFormat('EEEE').format(_selectedDate);
    final selectedDateStr = _formatDate(_selectedDate);
    return _schedules.where((s) {
      final isDay = s.operatingDays != null && s.operatingDays!.contains(selectedWeekday);
      final isDate = s.date != null && s.date == selectedDateStr;
      return isDay || isDate;
    }).length;
  }

  int get activeSchedulesToday {
    final selectedWeekday = DateFormat('EEEE').format(_selectedDate);
    final selectedDateStr = _formatDate(_selectedDate);
    final todaySchedules = _schedules.where((s) {
      final isDay = s.operatingDays != null && s.operatingDays!.contains(selectedWeekday);
      final isDate = s.date != null && s.date == selectedDateStr;
      return isDay || isDate;
    }).toList();

    int count = 0;
    for (var schedule in todaySchedules) {
      final isAnyBusCovering = _allBuses.any((bus) {
        final busNum = (bus['busNumber'] ?? '').toString().toLowerCase().trim();
        final sBus = (schedule.busNumber ?? '').toLowerCase().trim();
        if (sBus == busNum && busNum.isNotEmpty) return true;

        final sFrom = schedule.from.toLowerCase().trim();
        final sTo = schedule.to.toLowerCase().trim();
        final busFrom = (bus['from'] ?? '').toString().toLowerCase().trim();
        final busTo = (bus['to'] ?? '').toString().toLowerCase().trim();
        return sFrom == busFrom && sTo == busTo;
      });
      if (isAnyBusCovering) count++;
    }
    return count;
  }

  // --- Calendar ---
  List<DateTime> get daysInMonth {
    final lastDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    return List.generate(
      lastDayOfMonth.day,
      (index) => DateTime(_currentMonth.year, _currentMonth.month, index + 1),
    );
  }

  String get monthName {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[_currentMonth.month - 1];
  }

  String getWeekdayName(DateTime date) {
    return _weekdays[date.weekday - 1];
  }

  void changeMonth(int offset) {
    _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + offset);
    if (_currentMonth.year == DateTime.now().year && _currentMonth.month == DateTime.now().month) {
      _selectedDate = DateTime.now();
    } else {
      _selectedDate = DateTime(_currentMonth.year, _currentMonth.month, 1);
    }
    notifyListeners();
  }

  void selectDate(DateTime date) {
    _selectedDate = date;
    notifyListeners();
  }

  Future<void> forceStopTracking(Map<String, dynamic> bus) async {
    final busId = (bus['id'] ?? '').toString();
    final busNumber = (bus['busNumber'] ?? '').toString();
    final driverId = (bus['driverId'] ?? '').toString();
    final tripId = (bus['tripId'] ?? '').toString();

    if (busId.isEmpty) return;

    // 1. Remove from active buses in RTDB using the actual key
    await _busesRef.child(busId).remove();

    // Also remove by busNumber if it exists and is different from busId
    if (busNumber.isNotEmpty && busNumber != busId) {
      await _busesRef.child(busNumber).remove();
    }

    // 2. Clear local selection if this was the selected bus
    if (_selectedBusId == busId || _selectedBusId == busNumber) {
      _selectedBusId = null;
    }

    // 3. Mark trip as cancelled/force_stopped in RTDB trips collection
    if (driverId.isNotEmpty && tripId.isNotEmpty) {
      await FirebaseDatabase.instance.ref('trips').child(driverId).child(tripId).update({
        'endTime': ServerValue.timestamp,
        'status': 'force_stopped',
      });
    }

    // 4. Update Firestore drivers collection to Offline status
    if (driverId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('drivers').doc(driverId).update({
          'status': 'Offline',
        });
      } catch (e) {
        debugPrint("Error updating driver status: $e");
      }
    }

    // 5. Update Firestore trips and active_trips collections
    if (tripId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('trips').doc(tripId).update({
          'endTime': FieldValue.serverTimestamp(),
          'status': 'force_stopped',
        });
      } catch (e) {
        debugPrint("Error updating Firestore trips: $e");
      }

      try {
        await FirebaseFirestore.instance.collection('active_trips').doc(tripId).delete();
      } catch (e) {
        debugPrint("Error deleting active trip: $e");
      }

      // Add to completed_trips collection as 'force_stopped'
      try {
        await FirebaseFirestore.instance.collection('completed_trips').doc(tripId).set({
          'tripId': tripId,
          'driverId': driverId,
          'driverName': bus['driverName'] ?? 'Driver',
          'busNumber': busNumber,
          'plateNumber': bus['plateNumber'] ?? '',
          'from': bus['from'] ?? 'Unknown',
          'to': bus['to'] ?? 'Unknown',
          'gender': bus['gender'] ?? 'Combined',
          'startTime': FieldValue.serverTimestamp(),
          'endTime': FieldValue.serverTimestamp(),
          'status': 'force_stopped',
          'scheduleId': bus['scheduleId'] ?? '',
          'date': DateTime.now().toIso8601String().substring(0, 10),
          'revenue': 0.0,
        });
      } catch (e) {
        debugPrint("Error creating completed trip record: $e");
      }
    }
    notifyListeners();
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    _busesSubscription?.cancel();
    _schedulesSubscription?.cancel();
    _polylinesSubscription?.cancel();
    super.dispose();
  }
}
