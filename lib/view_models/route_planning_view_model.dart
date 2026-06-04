import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:unitransit_admin/core/services/firebase_service.dart';
import 'package:unitransit_admin/models/bus_schedule_model.dart';
import 'package:unitransit_admin/models/hub_model.dart';
import 'package:unitransit_admin/models/stop_model.dart';

class RoutePlanningViewModel extends ChangeNotifier {
  final FirebaseService _firebaseService;

  RoutePlanningViewModel(this._firebaseService) {
    // Add listeners for smart parsing
    latController.addListener(() => _smartParse(latController, lngController));
    stopLatController.addListener(() => _smartParse(stopLatController, stopLngController));
  }

  void _smartParse(TextEditingController latCtrl, TextEditingController lngCtrl) {
    String text = latCtrl.text.trim();
    if (text.isEmpty) return;

    // 1. Check for Comma Separated (Decimal): "29.37, 71.72"
    if (text.contains(',')) {
      final parts = text.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) {
          latCtrl.text = lat.toStringAsFixed(6);
          lngCtrl.text = lng.toStringAsFixed(6);
          notifyListeners();
          return;
        }
      }
    }

    // 2. Check for Space Separated (Decimal): "29.37 71.72"
    if (text.contains(' ') && !text.contains('°')) {
       final parts = text.split(' ');
       if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) {
          latCtrl.text = lat.toStringAsFixed(6);
          lngCtrl.text = lng.toStringAsFixed(6);
          notifyListeners();
          return;
        }
      }
    }

    // 3. Check for DMS Format: "29°23'16.70"N 71°42'11.46"E"
    final dmsRegex = RegExp(r'(\d+)°(\d+)\x27([\d\.]+)\x22([NSEW])');
    final matches = dmsRegex.allMatches(text).toList();
    
    if (matches.length == 2) {
      double parseDMS(RegExpMatch m) {
        double d = double.parse(m.group(1)!);
        double min = double.parse(m.group(2)!);
        double s = double.parse(m.group(3)!);
        String dir = m.group(4)!;
        
        double decimal = d + (min / 60) + (s / 3600);
        if (dir == 'S' || dir == 'W') decimal = -decimal;
        return decimal;
      }

      final lat = parseDMS(matches[0]);
      final lng = parseDMS(matches[1]);
      
      latCtrl.text = lat.toStringAsFixed(6);
      lngCtrl.text = lng.toStringAsFixed(6);
      notifyListeners();
    }
  }

  // --- Hubs Manager State ---
  final nameController = TextEditingController();
  final latController = TextEditingController();
  final lngController = TextEditingController();
  bool _isHubSaving = false;
  String? _editingHubName;

  bool get isHubSaving => _isHubSaving;
  String? get editingHubName => _editingHubName;

  void setEditingHub(HubModel? hub) {
    if (hub != null) {
      _editingHubName = hub.name;
      nameController.text = hub.name;
      latController.text = hub.latitude.toString();
      lngController.text = hub.longitude.toString();
    } else {
      _editingHubName = null;
      nameController.clear();
      latController.clear();
      lngController.clear();
    }
    notifyListeners();
  }

  Future<void> saveHub() async {
    if (nameController.text.isNotEmpty &&
        latController.text.isNotEmpty &&
        lngController.text.isNotEmpty) {
      _isHubSaving = true;
      notifyListeners();

      try {
        final hub = HubModel(
          name: nameController.text.trim(),
          latitude: double.parse(latController.text),
          longitude: double.parse(lngController.text),
        );

        if (_editingHubName != null) {
          await _firebaseService.updateHub(hub, _editingHubName!);
        } else {
          await _firebaseService.addHub(hub);
        }
        setEditingHub(null); // Reset
      } finally {
        _isHubSaving = false;
        notifyListeners();
      }
    }
  }

  Future<void> deleteHub(String name) async {
    await _firebaseService.deleteHub(name);
    notifyListeners();
  }

  // --- Route Definition State ---
  final routeNameController = TextEditingController();
  String? _fromHub;
  String? _toHub;
  String? _selectedType;
  bool _isRouteSaving = false;
  String? _editingRouteId;
  String? _originalRouteName;

  String? get fromHub => _fromHub;
  String? get toHub => _toHub;
  String? get selectedType => _selectedType;
  bool get isRouteSaving => _isRouteSaving;
  String? get editingRouteId => _editingRouteId;

  void setFromHub(String? hub) {
    _fromHub = hub;
    notifyListeners();
  }

  void setToHub(String? hub) {
    _toHub = hub;
    notifyListeners();
  }

  void setSelectedType(String? type) {
    _selectedType = type;
    notifyListeners();
  }

  void setEditingRoute(BusSchedule? route) {
    if (route != null) {
      _editingRouteId = route.id;
      _originalRouteName = route.route;
      routeNameController.text = route.route;
      _fromHub = route.from;
      _toHub = route.to;
      _selectedType = route.type;
    } else {
      _editingRouteId = null;
      _originalRouteName = null;
      routeNameController.clear();
      _fromHub = null;
      _toHub = null;
      _selectedType = null;
    }
    notifyListeners();
  }

  Future<void> saveRoute() async {
    if (routeNameController.text.isNotEmpty && _fromHub != null && _toHub != null) {
      _isRouteSaving = true;
      notifyListeners();

      try {
        final schedule = BusSchedule(
          id: _editingRouteId ?? DateTime.now().millisecondsSinceEpoch.toString(),
          route: routeNameController.text,
          from: _fromHub!,
          to: _toHub!,
          stops: [_fromHub!, _toHub!],
          type: _selectedType ?? 'Combined',
        );

        if (_editingRouteId != null) {
          await _firebaseService.updateBusSchedule(_editingRouteId!, schedule, _originalRouteName!);
        } else {
          await _firebaseService.addBusSchedule(schedule);
        }
        setEditingRoute(null);
      } finally {
        _isRouteSaving = false;
        notifyListeners();
      }
    }
  }

  Future<void> deleteRoute(String id, String routeName) async {
    await _firebaseService.deleteBusSchedule(id, routeName, forceDeleteRoute: true);
    notifyListeners();
  }

  // --- Polyline Uploader State ---
  final jsonController = TextEditingController();
  String? _selectedRouteForPolyline;
  bool _isPolylineSaving = false;

  String? get selectedRouteForPolyline => _selectedRouteForPolyline;
  bool get isPolylineSaving => _isPolylineSaving;

  void setSelectedRouteForPolyline(String? route) {
    _selectedRouteForPolyline = route;
    notifyListeners();
  }

  Future<void> uploadPolyline() async {
    if (_selectedRouteForPolyline == null || jsonController.text.trim().isEmpty) {
      return;
    }

    _isPolylineSaving = true;
    notifyListeners();

    try {
      final input = jsonController.text.trim();
      List<Map<String, double>> parsedCoords = [];

      // 1. Try standard JSON first
      try {
        final decoded = jsonDecode(input);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final lat = double.tryParse(item['lat']?.toString() ?? '');
              final lng = double.tryParse(item['lng']?.toString() ?? '');
              if (lat != null && lng != null) {
                parsedCoords.add({'lat': lat, 'lng': lng});
              }
            } else if (item is List && item.length >= 2) {
              final lat = double.tryParse(item[0]?.toString() ?? '');
              final lng = double.tryParse(item[1]?.toString() ?? '');
              if (lat != null && lng != null) {
                parsedCoords.add({'lat': lat, 'lng': lng});
              }
            }
          }
        }
      } catch (_) {
        // Not valid JSON, proceed to regex parser
      }

      // 2. If JSON parsing didn't find any coordinates, try Regex parsing (e.g. LatLng(29.39, 71.69) or raw pairs)
      if (parsedCoords.isEmpty) {
        // Regex to match "LatLng(29.39, 71.69)" or just numbers: "29.39, 71.69"
        final latLngRegex = RegExp(r'(?:LatLng\s*\(\s*)?([0-9.-]+)\s*,\s*([0-9.-]+)\s*\)?');
        final matches = latLngRegex.allMatches(input);
        
        for (final match in matches) {
          final lat = double.tryParse(match.group(1) ?? '');
          final lng = double.tryParse(match.group(2) ?? '');
          if (lat != null && lng != null) {
            parsedCoords.add({'lat': lat, 'lng': lng});
          }
        }
      }

      if (parsedCoords.isEmpty) {
        throw const FormatException("No coordinates could be parsed. Please check the format.");
      }

      await _firebaseService.savePolyline(_selectedRouteForPolyline!, parsedCoords);
      jsonController.clear();
    } catch (e) {
      debugPrint("Error saving polyline: $e");
      rethrow;
    } finally {
      _isPolylineSaving = false;
      notifyListeners();
    }
  }

  // --- Stop Manager State ---
  final stopNameController = TextEditingController();
  final stopLatController = TextEditingController();
  final stopLngController = TextEditingController();
  String? _selectedRouteForStop;
  bool _isStopSaving = false;
  String? _editingStopId;

  String? get selectedRouteForStop => _selectedRouteForStop;
  bool get isStopSaving => _isStopSaving;
  String? get editingStopId => _editingStopId;

  void setSelectedRouteForStop(String? route) {
    _selectedRouteForStop = route;
    notifyListeners();
  }

  void setEditingStop(StopModel? stop) {
    if (stop != null) {
      _editingStopId = stop.id;
      stopNameController.text = stop.name;
      stopLatController.text = stop.latitude.toString();
      stopLngController.text = stop.longitude.toString();
      _selectedRouteForStop = stop.route;
    } else {
      _editingStopId = null;
      stopNameController.clear();
      stopLatController.clear();
      stopLngController.clear();
      _selectedRouteForStop = null;
    }
    notifyListeners();
  }

  Future<void> saveStop() async {
    if (stopNameController.text.isNotEmpty &&
        stopLatController.text.isNotEmpty &&
        stopLngController.text.isNotEmpty &&
        _selectedRouteForStop != null) {
      _isStopSaving = true;
      notifyListeners();

      try {
        final stop = StopModel(
          id: _editingStopId ?? DateTime.now().millisecondsSinceEpoch.toString(),
          name: stopNameController.text.trim(),
          latitude: double.parse(stopLatController.text),
          longitude: double.parse(stopLngController.text),
          route: _selectedRouteForStop!,
        );

        if (_editingStopId != null) {
          await _firebaseService.updateStop(stop);
        } else {
          await _firebaseService.addStop(stop);
        }
        setEditingStop(null);
      } finally {
        _isStopSaving = false;
        notifyListeners();
      }
    }
  }

  Future<void> deleteStop(String id) async {
    await _firebaseService.deleteStop(id);
    notifyListeners();
  }

  @override
  void dispose() {
    nameController.dispose();
    latController.dispose();
    lngController.dispose();
    routeNameController.dispose();
    jsonController.dispose();
    stopNameController.dispose();
    stopLatController.dispose();
    stopLngController.dispose();
    super.dispose();
  }
}
