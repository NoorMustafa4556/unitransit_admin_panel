import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_database/firebase_database.dart' hide Query;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:unitransit_admin/models/driver_model.dart';
import 'package:unitransit_admin/models/student_model.dart';
import 'package:unitransit_admin/models/bus_schedule_model.dart';
import 'package:unitransit_admin/models/hub_model.dart';
import 'package:unitransit_admin/models/stop_model.dart';
import 'package:unitransit_admin/models/support_ticket_model.dart';
import 'package:unitransit_admin/models/faq_model.dart';
import 'package:unitransit_admin/models/audit_log_model.dart';

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  // Create User Authentication without logging out the current admin
  Future<String> createUserAuth(String email, String password) async {
    try {
      // Use a secondary app instance to avoid logging out the current admin user
      FirebaseApp secondaryApp;
      try {
        secondaryApp = Firebase.app('SecondaryApp');
      } catch (e) {
        secondaryApp = await Firebase.initializeApp(
          name: 'SecondaryApp',
          options: Firebase.app().options,
        );
      }

      final credential = await FirebaseAuth.instanceFor(
        app: secondaryApp,
      ).createUserWithEmailAndPassword(email: email, password: password);

      final uid = credential.user!.uid;

      // Delete the secondary app instance to clean up
      await secondaryApp.delete();
      return uid;
    } catch (e) {
      throw 'Authentication creation failed: $e';
    }
  }

  // Generic Image Upload
  Future<String> uploadImage(Uint8List fileBytes, String path) async {
    try {
      print("Starting image upload to path: $path");
      final ref = _storage.ref().child(path);
      final uploadTask = ref.putData(fileBytes);
      final snapshot = await uploadTask;
      String url = await snapshot.ref.getDownloadURL();
      print("Upload successful! URL obtained.");
      return url;
    } catch (e) {
      print("Image upload FAILED at $path: $e");
      rethrow;
    }
  }

  // Drivers
  Future<void> addDriver(DriverModel driver) async {
    await _db.collection('drivers').doc(driver.id).set(driver.toMap());
    await _db.collection('users').doc(driver.id).set({
      'uid': driver.id,
      'name': driver.name,
      'email': driver.email,
      'role': 'Driver',
      'isVerified': driver.isVerified,
      'isBlocked': driver.isBlocked,
      'status': driver.status,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await logActivity(action: 'Added Driver', target: 'Driver: ${driver.name}');
  }

  Stream<List<DriverModel>> getDrivers() {
    return _db
        .collection('drivers')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => DriverModel.fromMap(doc.data()))
              .toList();
        });
  }

  Future<void> updateDriver(DriverModel driver) async {
    await _db.collection('drivers').doc(driver.id).update(driver.toMap());
    try {
      await _db.collection('users').doc(driver.id).update({
        'isVerified': driver.isVerified,
        'isBlocked': driver.isBlocked,
        'status': driver.status,
        'name': driver.name,
      });
    } catch (_) {
      await _db.collection('users').doc(driver.id).set({
        'uid': driver.id,
        'name': driver.name,
        'email': driver.email,
        'role': 'Driver',
        'isVerified': driver.isVerified,
        'isBlocked': driver.isBlocked,
        'status': driver.status,
      }, SetOptions(merge: true));
    }
    await logActivity(
      action: 'Updated Driver',
      target: 'Driver: ${driver.name}',
    );
  }

  Future<void> deleteDriver(String id) async {
    // Note: In a real app, also delete images from storage
    try {
      final doc = await _db.collection('drivers').doc(id).get();
      final name = doc.data()?['name'] ?? id;
      await _db.collection('drivers').doc(id).delete();
      await _db.collection('users').doc(id).delete();
      await logActivity(action: 'Deleted Driver', target: 'Driver: $name');
    } catch (e) {
      await _db.collection('drivers').doc(id).delete();
      await _db.collection('users').doc(id).delete();
    }
  }

  Future<void> resetDriverPassword(String email) async {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  Future<void> resetStudentPassword(String email) async {
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  // Students
  Future<void> addStudent(StudentModel student) async {
    await _db.collection('users').doc(student.id).set(student.toMap());
    await _db
        .collection('students')
        .doc(student.id)
        .set(student.toMap(), SetOptions(merge: true));
    await logActivity(
      action: 'Added Student',
      target: 'Student: ${student.name}',
    );
  }

  Stream<List<StudentModel>> getStudents() {
    return _db
        .collection('users')
        .where('role', isEqualTo: 'Student')
        .snapshots()
        .map((snapshot) {
          final students =
              snapshot.docs
                  .map((doc) => StudentModel.fromMap(doc.data(), docId: doc.id))
                  .toList();
          students.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return students;
        });
  }

  Future<void> updateStudent(StudentModel student) async {
    await _db.collection('users').doc(student.id).update(student.toMap());
    try {
      await _db.collection('students').doc(student.id).update(student.toMap());
    } catch (_) {
      await _db
          .collection('students')
          .doc(student.id)
          .set(student.toMap(), SetOptions(merge: true));
    }
  }

  Future<void> deleteStudent(String id) async {
    try {
      final doc = await _db.collection('users').doc(id).get();
      final name = doc.data()?['name'] ?? id;
      await _db.collection('users').doc(id).delete();
      await logActivity(action: 'Deleted Student', target: 'Student: $name');
    } catch (e) {
      await _db.collection('users').doc(id).delete();
    }
  }

  // Routes & Schedules
  Stream<List<BusSchedule>> getBusSchedules() {
    return _db.collection('schedules').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => BusSchedule.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  Future<void> addBusSchedule(BusSchedule schedule) async {
    // 1. Save to Firestore (Detailed Info)
    await _db.collection('schedules').doc(schedule.id).set(schedule.toMap());

    // 2. Save to Realtime Database (Dropdown Info for Student App)
    await _rtdb.ref('official_routes').child(schedule.route).set({
      'from': schedule.from,
      'to': schedule.to,
    });
  }

  Future<void> deleteBusSchedule(String id, String routeName, {bool forceDeleteRoute = false}) async {
    // 0. Clean up driver assignment
    try {
      final scheduleDoc = await _db.collection('schedules').doc(id).get();
      if (scheduleDoc.exists) {
        final driverId = scheduleDoc.data()?['assignedDriverId'];
        if (driverId != null && driverId.toString().isNotEmpty) {
          final driverDoc = await _db.collection('drivers').doc(driverId).get();
          if (driverDoc.exists) {
            final assignedRoutes = List<String>.from(
              driverDoc.data()?['assignedRoutes'] ?? [],
            );
            assignedRoutes.remove(id);

            // Recompute bus numbers for this driver
            final busNumbers = <String>{};
            for (final sid in assignedRoutes) {
              final sDoc = await _db.collection('schedules').doc(sid).get();
              if (sDoc.exists) {
                final bn = sDoc.data()?['busNumber'] ?? '';
                if (bn.toString().isNotEmpty && bn != 'TBA') busNumbers.add(bn);
              }
            }

            await _db.collection('drivers').doc(driverId).update({
              'assignedRoutes': assignedRoutes,
              'assignedBus': busNumbers.join(', '),
            });
          }
        }
      }
    } catch (e) {
      print("Error cleaning up driver assignment on schedule delete: $e");
    }

    if (forceDeleteRoute) {
      // 1. Delete from Firestore
      await _db.collection('schedules').doc(id).delete();

      // 2. Delete from Realtime Database
      await _rtdb.ref('official_routes').child(routeName).remove();
      
      // 3. Keep custom polylines and stops intact as requested by the user
    } else {
      // Just delete the schedule from Firestore without affecting the official route
      await _db.collection('schedules').doc(id).delete();
    }
  }

  // Hub Management (RTDB)
  Future<void> addHub(HubModel hub) async {
    await _rtdb.ref('hubs').child(hub.name).set(hub.toMap());
  }

  Future<void> updateHub(HubModel hub, String oldName) async {
    if (hub.name != oldName) {
      await _rtdb.ref('hubs').child(oldName).remove();

      // Optional: Update all routes that use this hub name
      final routesData = await _rtdb.ref('official_routes').get();
      if (routesData.exists) {
        final Map<dynamic, dynamic> routes =
            routesData.value as Map<dynamic, dynamic>;
        routes.forEach((key, value) async {
          final Map<dynamic, dynamic> route = value as Map<dynamic, dynamic>;
          bool changed = false;
          if (route['from'] == oldName) {
            route['from'] = hub.name;
            changed = true;
          }
          if (route['to'] == oldName) {
            route['to'] = hub.name;
            changed = true;
          }
          if (changed) {
            await _rtdb
                .ref('official_routes')
                .child(key)
                .update(Map<String, dynamic>.from(route));
          }
        });
      }
    }
    await _rtdb.ref('hubs').child(hub.name).set(hub.toMap());
  }

  Stream<List<HubModel>> getHubs() {
    return _rtdb.ref('hubs').onValue.map((event) {
      final data = event.snapshot.value;
      if (data is! Map) return [];
      return data.entries.map((e) {
        final val = e.value;
        return HubModel.fromMap(
          e.key.toString(),
          val is Map ? Map<dynamic, dynamic>.from(val) : {},
        );
      }).toList();
    });
  }

  Future<void> deleteHub(String name) async {
    await _rtdb.ref('hubs').child(name).remove();
  }

  // Polyline Management (RTDB)
  Future<void> savePolyline(String routeName, List<dynamic> coordinates) async {
    await _rtdb.ref('custom_polylines').child(routeName).set(coordinates);
  }

  // Stop Management (RTDB)
  Future<void> addStop(StopModel stop) async {
    await _rtdb.ref('stops').child(stop.id).set(stop.toMap());
  }

  Future<void> updateStop(StopModel stop) async {
    await _rtdb.ref('stops').child(stop.id).update(stop.toMap());
  }

  Future<void> deleteStop(String id) async {
    await _rtdb.ref('stops').child(id).remove();
  }

  Stream<List<StopModel>> getStops() {
    return _rtdb.ref('stops').onValue.map((event) {
      final data = event.snapshot.value;
      if (data is! Map) return [];
      return data.entries.map((e) {
        final val = e.value;
        return StopModel.fromMap(
          e.key.toString(),
          val is Map ? Map<dynamic, dynamic>.from(val) : {},
        );
      }).toList();
    });
  }

  Future<void> updateBusSchedule(
    String id,
    BusSchedule schedule,
    String oldRouteName,
  ) async {
    // 1. Update Firestore
    await _db.collection('schedules').doc(id).update(schedule.toMap());

    // 2. Update RTDB (official_routes)
    if (schedule.route != oldRouteName) {
      await _rtdb.ref('official_routes').child(oldRouteName).remove();
      // Also move polyline if exists
      final polylineData =
          await _rtdb.ref('custom_polylines').child(oldRouteName).get();
      if (polylineData.exists) {
        await _rtdb
            .ref('custom_polylines')
            .child(schedule.route)
            .set(polylineData.value);
        await _rtdb.ref('custom_polylines').child(oldRouteName).remove();
      }
    }

    await _rtdb.ref('official_routes').child(schedule.route).set({
      'from': schedule.from,
      'to': schedule.to,
    });
  }

  Stream<Map<String, dynamic>> getPolylinesStatus() {
    return _rtdb.ref('custom_polylines').onValue.map((event) {
      final data = event.snapshot.value;
      if (data is! Map) return {};
      return Map<String, dynamic>.from(data);
    });
  }

  // Real-time Stats Stream
  Stream<Map<String, dynamic>> getStatsStream() {
    return getRealTimeStats();
  }

  Stream<Map<String, dynamic>> getRealTimeStats() {
    late StreamController<Map<String, dynamic>> controller;
    StreamSubscription? driverSub;
    StreamSubscription? studentSub;
    StreamSubscription? tripsSub;
    StreamSubscription? busesSub;

    int drivers = 0;
    int students = 0;
    int activeTripsCount = 0;
    double revenue = 0.0;

    void updateStats() {
      if (!controller.isClosed) {
        controller.add({
          'totalDrivers': drivers,
          'totalStudents': students,
          'activeTrips': activeTripsCount,
          'totalRevenue': revenue,
        });
      }
    }

    controller = StreamController<Map<String, dynamic>>.broadcast(
      onListen: () {
        driverSub = _db.collection('drivers').snapshots().listen((snap) {
          drivers = snap.docs.length;
          updateStats();
        });

        studentSub = _db
            .collection('users')
            .where('role', isEqualTo: 'Student')
            .snapshots()
            .listen((snap) {
              students = snap.docs.length;
              updateStats();
            });

        // Truly Real-time Active Trips count from RTDB buses node
        busesSub = _rtdb.ref('buses').onValue.listen((event) {
          final data = event.snapshot.value;
          if (data is Map) {
            activeTripsCount = data.length;
          } else {
            activeTripsCount = 0;
          }
          updateStats();
        });

        tripsSub = _db.collection('completed_trips').snapshots().listen((
          snap,
        ) async {
          double tempRevenue = 0.0;
          for (var doc in snap.docs) {
            final data = doc.data();
            final amount =
                data['revenue'] ??
                data['fare'] ??
                data['amount'] ??
                data['totalPrice'] ??
                data['price'] ??
                0;
            tempRevenue += (amount is num ? amount.toDouble() : 0.0);
          }

          revenue = tempRevenue;
          updateStats();
        });
      },
      onCancel: () {
        driverSub?.cancel();
        studentSub?.cancel();
        tripsSub?.cancel();
        busesSub?.cancel();
      },
    );

    return controller.stream;
  }

  Future<int> getAdminsCount() async {
    final snapshot =
        await _db.collection('users').where('role', isEqualTo: 'Admin').get();
    return snapshot.docs.length;
  }

  // Gender Configuration (RTDB)
  Future<void> updateGenderConfig(String name, String colorHex) async {
    await _rtdb.ref('gender_configs').child(name).set({'color': colorHex});
  }

  Future<void> deleteGenderConfig(String name) async {
    await _rtdb.ref('gender_configs').child(name).remove();
  }

  Stream<Map<String, String>> getGenderConfigs() async* {
    yield {
      'Girls Special': '#E91E63',
      'Boys Special': '#2196F3',
      'Combined': '#9C27B0',
    };
    try {
      await for (final event in _rtdb.ref('gender_configs').onValue) {
        final data = event.snapshot.value;
        if (data is Map) {
          final Map<String, String> result = {};
          data.forEach((key, value) {
            if (value is Map) {
              final color = value['color'];
              if (color != null) {
                result[key.toString()] = color.toString();
              }
            }
          });
          if (result.isNotEmpty) {
            yield result;
          }
        }
      }
    } catch (e) {
      print("FirebaseService: Error listening to gender configs: $e. Using defaults.");
    }
  }

  // Support Tickets
  Stream<List<SupportTicketModel>> getTickets() {
    return _db
        .collection('support_tickets')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => SupportTicketModel.fromMap(doc.id, doc.data()))
              .toList();
        });
  }

  Future<void> updateTicketStatus(
    String ticketId,
    String status, {
    String? reply,
  }) async {
    final Map<String, dynamic> updates = {'status': status, 'adminRead': true};
    if (reply != null) {
      updates['adminReply'] = reply;
      updates['userRead'] = false;
    }
    if (status.toLowerCase() == 'resolved' ||
        status.toLowerCase() == 'closed') {
      updates['resolvedAt'] = Timestamp.now();
    }

    // Update the ticket
    await _db.collection('support_tickets').doc(ticketId).update(updates);

    // If a reply is provided, write a real-time notification to the user's notifications collection
    if (reply != null && reply.trim().isNotEmpty) {
      try {
        final docSnapshot =
            await _db.collection('support_tickets').doc(ticketId).get();
        if (docSnapshot.exists) {
          final data = docSnapshot.data();
          final String? userId = data?['userId'];
          final String? userRole = data?['userRole'];

          if (userId != null && userId.isNotEmpty) {
            final notificationData = {
              'title': 'Support Ticket Update',
              'message': 'Your support query has been resolved: "$reply"',
              'timestamp': FieldValue.serverTimestamp(),
              'type': 'support',
              'isRead': false,
              'targetRole': userRole ?? 'Student',
            };

            // Write to user private notifications subcollection
            await _db
                .collection('users')
                .doc(userId)
                .collection('notifications')
                .add(notificationData);

            // Write to global notifications trigger collection for FCM / functions triggers
            await _db.collection('notifications').add({
              ...notificationData,
              'userId': userId,
              'ticketId': ticketId,
            });
          }
        }
      } catch (e) {
        print('Error generating reply notification: $e');
      }
    }
  }

  Future<void> markTicketAsRead(String ticketId) async {
    try {
      await _db.collection('support_tickets').doc(ticketId).update({
        'adminRead': true,
      });
    } catch (e) {
      print('Error marking ticket as read: $e');
    }
  }

  Future<void> markEmergencyAlertAsRead(String alertId) async {
    try {
      await _rtdb.ref('emergency_alerts').child(alertId).update({
        'adminRead': true,
      });
    } catch (e) {
      print('Error marking emergency alert as read: $e');
    }
  }

  // App Settings / About Info
  Future<void> uploadInitialAppInfo() async {
    final doc = await _db.collection('app_settings').doc('about').get();
    if (!doc.exists) {
      await _db.collection('app_settings').doc('about').set({
        'vision':
            "UniTransit is a state-of-the-art solution designed for The Islamia University of Bahawalpur to digitize the bus tracking experience. It leverages real-time GPS data, Firebase synchronization, and smart routing algorithms to ensure students never miss their commute.",
        'version': "1.2.0 (Stable)",
        'university': "The Islamia University of Bahawalpur",
        'appLogoUrl': "", // Add image URL here later from Admin Panel
        'contributors': [
          {
            "role": "Lead Developer",
            "name": "Noor Mustafa",
            "subtitle": "Roll No: F22BDOCS1M01160",
          },
          {
            "role": "Supervisor",
            "name": "Dr. Umar Farooq Shafi",
            "subtitle": "Department of CS & IT, IUB",
          },
        ],
      });
    }
  }

  // FAQs
  Stream<List<FaqModel>> getFaqs() {
    return _db.collection('faqs').orderBy('order').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => FaqModel.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  Future<void> addFaq(FaqModel faq) async {
    await _db.collection('faqs').add(faq.toMap());
  }

  Future<void> updateFaq(FaqModel faq) async {
    await _db.collection('faqs').doc(faq.id).update(faq.toMap());
  }

  Future<void> deleteFaq(String id) async {
    await _db.collection('faqs').doc(id).delete();
  }

  Future<void> updateAppInfo(Map<String, dynamic> data) async {
    await _db.collection('app_settings').doc('about').set(data);
  }

  // Send notification to a specific user (student/driver)
  Future<void> sendUserNotification({
    required String userId,
    required String title,
    required String message,
    required String type, // 'info', 'alert', 'system', 'sos_resolved'
    String? imageUrl,
    Map<String, dynamic>? extraData,
  }) async {
    final timestamp = Timestamp.now();

    // 1. Save to user private notifications subcollection
    final payload = {
      'title': title,
      'message': message,
      'timestamp': timestamp,
      'type': type,
      'isRead': false,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (extraData != null) ...extraData,
    };

    await _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .add(payload);

    // 2. Log in global admin_notifications for tracking
    await _db.collection('admin_notifications').add({
      'title': title,
      'message': message,
      'targetAudience': 'Specific User ($userId)',
      'type': type,
      'timestamp': timestamp,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (extraData != null) ...extraData,
    });
  }

  // Send Custom Broadcast Notifications to Students, Drivers, or All
  Future<void> sendCustomNotification({
    required String title,
    required String message,
    required String targetAudience, // 'Students', 'Drivers', 'All'
    required String type, // 'info', 'alert', 'system'
    String? imageUrl,
  }) async {
    final timestamp = Timestamp.now();

    // 1. Save to global admin_notifications collection
    final newAlert = {
      'title': title,
      'message': message,
      'targetAudience': targetAudience,
      'type': type,
      'timestamp': timestamp,
      if (imageUrl != null) 'imageUrl': imageUrl,
    };
    await _db.collection('admin_notifications').add(newAlert);

    // 2. Fetch users based on targetAudience
    Query query = _db.collection('users');
    if (targetAudience == 'Students') {
      query = query.where('role', isEqualTo: 'Student');
    } else if (targetAudience == 'Drivers') {
      query = query.where('role', isEqualTo: 'Driver');
    }

    final usersSnapshot = await query.get();
    if (usersSnapshot.docs.isNotEmpty) {
      WriteBatch batch = _db.batch();
      int operationCount = 0;

      for (var doc in usersSnapshot.docs) {
        final notificationRef =
            _db
                .collection('users')
                .doc(doc.id)
                .collection('notifications')
                .doc();

        batch.set(notificationRef, {
          'title': title,
          'message': message,
          'timestamp': timestamp,
          'type': type,
          'isRead': false,
          if (imageUrl != null) 'imageUrl': imageUrl,
        });

        operationCount++;
        // Firestore batch limit is 500
        if (operationCount >= 450) {
          await batch.commit();
          batch = _db.batch();
          operationCount = 0;
        }
      }

      if (operationCount > 0) {
        await batch.commit();
      }
    }
  }

  // Get sent admin notifications stream
  Stream<List<Map<String, dynamic>>> getSentNotifications() {
    return _db
        .collection('admin_notifications')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'title': data['title'] ?? '',
              'message': data['message'] ?? '',
              'targetAudience': data['targetAudience'] ?? 'All',
              'type': data['type'] ?? 'info',
              'imageUrl': data['imageUrl'],
              'timestamp':
                  (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            };
          }).toList();
        });
  }

  // Fetch all users eligible for receiving notifications (Students and Drivers)
  Future<List<Map<String, dynamic>>> getAllNotificationUsers() async {
    final snapshot = await _db.collection('users').get();
    return snapshot.docs
        .where((doc) {
          final role = (doc.data()['role'] ?? '').toString().toLowerCase();
          return role == 'student' || role == 'driver';
        })
        .map(
          (doc) => {
            'uid': doc.id,
            'name': doc.data()['name'] ?? 'Unnamed',
            'email': doc.data()['email'] ?? '',
            'role': doc.data()['role'] ?? 'Student',
          },
        )
        .toList();
  }

  // Emergency Alerts (RTDB)
  Stream<List<Map<String, dynamic>>> getEmergencyAlerts() {
    return _rtdb.ref('emergency_alerts').onValue.map((event) {
      final data = event.snapshot.value;
      if (data is! Map) return [];

      final List<Map<String, dynamic>> alerts = [];
      data.forEach((key, value) {
        if (value is Map) {
          final alert = Map<String, dynamic>.from(value);
          alert['id'] = key.toString();
          alerts.add(alert);
        }
      });

      // Sort by timestamp descending
      alerts.sort((a, b) {
        final aTime = a['timestamp'] ?? 0;
        final bTime = b['timestamp'] ?? 0;
        return bTime.compareTo(aTime);
      });

      return alerts;
    });
  }

  Future<void> resolveEmergencyAlert(
    String id, {
    String? notes,
    String? resolvedBy,
  }) async {
    try {
      final alertSnapshot = await _rtdb.ref('emergency_alerts').child(id).get();
      if (alertSnapshot.exists) {
        final alertData = alertSnapshot.value as Map?;
        final String? userId = alertData?['userId']?.toString();
        if (userId != null && userId.isNotEmpty) {
          await sendUserNotification(
            userId: userId,
            title: 'SOS Alert Resolved 🟢',
            message:
                'Admin resolved your SOS: "${notes ?? 'Incident Handled'}". Please rate our assistance.',
            type: 'sos_resolved',
            extraData: {
              'alertId': id,
              'alertMessage': alertData?['message'] ?? 'Emergency SOS Alert',
            },
          );
        }
      }
    } catch (e) {
      print("Error triggering SOS resolution notification: $e");
    }

    await _rtdb.ref('emergency_alerts').child(id).update({
      'status': 'resolved',
      'resolutionNotes': notes ?? 'Resolved by Admin',
      'resolvedBy': resolvedBy ?? 'Admin',
      'resolvedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // Trip History (RTDB)
  Stream<List<Map<String, dynamic>>> getTripHistoryStream() {
    return _rtdb.ref('driver_trips').onValue.map((event) {
      final List<Map<String, dynamic>> trips = [];
      final data = event.snapshot.value;
      if (data is Map) {
        data.forEach((driverId, driverTrips) {
          if (driverTrips is Map) {
            driverTrips.forEach((tripId, tripData) {
              if (tripData is Map) {
                final trip = Map<String, dynamic>.from(tripData);
                trip['driverId'] = driverId.toString();
                trip['tripId'] = tripId.toString();
                trips.add(trip);
              }
            });
          }
        });
      }
      // Sort by startTime descending (newest first)
      trips.sort((a, b) {
        final aTime = a['startTime'] ?? 0;
        final bTime = b['startTime'] ?? 0;
        return bTime.compareTo(aTime);
      });
      return trips;
    });
  }

  // Trip Alerts (RTDB)
  Stream<Map<String, dynamic>> getTripAlertsStream() {
    return _rtdb.ref('trip_alerts').onChildAdded.map((event) {
      final value = event.snapshot.value;
      if (value is Map) {
        final alert = Map<String, dynamic>.from(value);
        alert['id'] = event.snapshot.key;
        return alert;
      }
      return {};
    });
  }

  // Audit Logs
  Future<void> logActivity({
    required String action,
    required String target,
    String? details,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final adminDoc = await _db.collection('users').doc(user.uid).get();
      final adminName =
          adminDoc.data()?['name'] ??
          user.displayName ??
          user.email ??
          'Unknown Admin';

      await _db.collection('audit_logs').add({
        'adminId': user.uid,
        'adminName': adminName,
        'action': action,
        'target': target,
        'timestamp': FieldValue.serverTimestamp(),
        'details': details,
      });
    } catch (e) {
      print("Failed to log activity: $e");
    }
  }

  Stream<List<AuditLogModel>> getAuditLogs() {
    return _db
        .collection('audit_logs')
        .orderBy('timestamp', descending: true)
        .limit(200)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => AuditLogModel.fromFirestore(doc))
              .toList();
        });
  }

  // ─── Safety Configuration (Firestore) ───────────────────────────────────
  Stream<Map<String, dynamic>> getSafetyConfig() {
    return _db
        .collection('app_settings')
        .doc('safety')
        .snapshots()
        .map((doc) {
          if (!doc.exists) {
            return {
              'speedLimit': 60.0,
              'geofencingEnabled': true,
              'overspeedingEnabled': true,
              'geofenceRadiusMeters': 200,
            };
          }
          final data = doc.data()!;
          return {
            'speedLimit': (data['speedLimit'] ?? 60).toDouble(),
            'geofencingEnabled': data['geofencingEnabled'] ?? true,
            'overspeedingEnabled': data['overspeedingEnabled'] ?? true,
            'geofenceRadiusMeters': data['geofenceRadiusMeters'] ?? 200,
          };
        });
  }

  Future<void> updateSafetyConfig(Map<String, dynamic> config) async {
    await _db.collection('app_settings').doc('safety').set({
      ...config,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await logActivity(
      action: 'Updated Safety Config',
      target: 'Speed Limit: ${config['speedLimit']} km/h',
    );
  }

  // ─── Real-Time Trip Analytics Stream (RTDB) ─────────────────────────────
  /// Returns aggregated analytics computed from driver_trips RTDB node.
  Stream<Map<String, dynamic>> getTripAnalyticsStream() {
    return _rtdb.ref('driver_trips').onValue.map((event) {
      final data = event.snapshot.value;
      if (data is! Map) {
        return <String, dynamic>{
          'totalTrips': 0,
          'completedTrips': 0,
          'successRate': 0.0,
          'peakHour': 0,
          'hourlyBuckets': List<int>.filled(24, 0),
        };
      }

      final List<Map<String, dynamic>> trips = [];
      data.forEach((driverId, driverTrips) {
        if (driverTrips is Map) {
          driverTrips.forEach((tripId, tripData) {
            if (tripData is Map) {
              final t = Map<String, dynamic>.from(tripData);
              t['driverId'] = driverId.toString();
              trips.add(t);
            }
          });
        }
      });

      int totalTrips = trips.length;
      int completedTrips =
          trips.where((t) => (t['status'] ?? '') == 'completed').length;
      double successRate =
          totalTrips > 0 ? (completedTrips / totalTrips) * 100 : 0.0;

      final List<int> hourlyBuckets = List<int>.filled(24, 0);
      for (var trip in trips) {
        final startTimeVal = trip['startTime'];
        if (startTimeVal != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(startTimeVal);
          hourlyBuckets[dt.hour]++;
        }
      }

      int peakHour = 0;
      for (int i = 1; i < 24; i++) {
        if (hourlyBuckets[i] > hourlyBuckets[peakHour]) peakHour = i;
      }

      return <String, dynamic>{
        'totalTrips': totalTrips,
        'completedTrips': completedTrips,
        'successRate': successRate,
        'peakHour': peakHour,
        'hourlyBuckets': hourlyBuckets,
      };
    });
  }

  // ─── Buses Stream (Firestore) ─────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> getBusesStream() {
    return _db.collection('buses').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }
}
