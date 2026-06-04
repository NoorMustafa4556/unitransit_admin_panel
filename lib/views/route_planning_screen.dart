import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:unitransit_admin/core/constants/app_colors.dart';
import 'package:unitransit_admin/core/services/firebase_service.dart';
import 'package:unitransit_admin/models/bus_schedule_model.dart';
import 'package:unitransit_admin/models/hub_model.dart';
import 'package:unitransit_admin/models/stop_model.dart';
import 'package:unitransit_admin/core/utils/responsive_util.dart';
import 'package:unitransit_admin/view_models/route_planning_view_model.dart';
import 'package:unitransit_admin/core/utils/animations.dart';

class RoutePlanningScreen extends StatefulWidget {
  const RoutePlanningScreen({super.key});

  @override
  State<RoutePlanningScreen> createState() => _RoutePlanningScreenState();
}

class _RoutePlanningScreenState extends State<RoutePlanningScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppResponsiveUtil.isMobile(context);
    
    return FadeInSlide(
      duration: const Duration(milliseconds: 600),
      child: SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              _buildTabBar(),
              const SizedBox(height: 24),
              Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      if (_tabController.index < _tabController.length - 1) {
                        _tabController.animateTo(_tabController.index + 1);
                        return KeyEventResult.handled;
                      }
                    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      if (_tabController.index > 0) {
                        _tabController.animateTo(_tabController.index - 1);
                        return KeyEventResult.handled;
                      }
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity != null) {
                      if (details.primaryVelocity! < -300) {
                        if (_tabController.index < _tabController.length - 1) {
                          _tabController.animateTo(_tabController.index + 1);
                        }
                      } else if (details.primaryVelocity! > 300) {
                        if (_tabController.index > 0) {
                          _tabController.animateTo(_tabController.index - 1);
                        }
                      }
                    }
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.05, 0.0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Builder(
                      key: ValueKey<int>(_tabController.index),
                      builder: (context) {
                        switch (_tabController.index) {
                          case 0:
                            return const HubsManagerSection();
                          case 1:
                            return const RouteDefinitionSection();
                          case 2:
                            return const StopsManagerSection();
                          case 3:
                            return const PolylineUploaderSection();
                          case 4:
                            return const MapPreviewSection();
                          default:
                            return const SizedBox.shrink();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildTabBar() {
    return FadeInSlide(
      direction: FadeInDirection.leftToRight,
      delay: const Duration(milliseconds: 100),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ScrollConfiguration(
          // Disable default web scrollbars on the tab bar itself
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textSecondary,
            indicator: BoxDecoration(
              color: AppColors.primaryNavy,
              borderRadius: BorderRadius.circular(10),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(text: 'Hubs'),
              Tab(text: 'Routes'),
              Tab(text: 'Stops'),
              Tab(text: 'Paths'),
              Tab(text: 'Map Preview'),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Section A: Hubs Manager ---
class HubsManagerSection extends StatelessWidget {
  const HubsManagerSection({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<RoutePlanningViewModel>();
    final firebaseService = context.read<FirebaseService>();
    final isDesktop = AppResponsiveUtil.isDesktop(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Flex(
        direction: isDesktop ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isDesktop ? 380 : double.infinity,
            child: _buildFormPanel(viewModel),
          ),
          if (isDesktop) const SizedBox(width: 24),
          if (!isDesktop) const SizedBox(height: 24),
          if (isDesktop)
            Expanded(child: _buildListPanel(firebaseService, viewModel))
          else
            _buildListPanel(firebaseService, viewModel),
        ],
      ),
    );
  }

  Widget _buildFormPanel(RoutePlanningViewModel viewModel) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            viewModel.editingHubName != null ? 'Edit Hub' : 'Create Hub',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark),
          ),
          const SizedBox(height: 24),
          _buildFieldLabel('Location Name'),
          _buildModernField(viewModel.nameController, 'e.g. Baghdad Campus', Icons.business_rounded),
          const SizedBox(height: 16),
          _buildFieldLabel('Latitude'),
          _buildModernField(viewModel.latController, 'e.g. 29.37', Icons.gps_fixed_rounded, isNumber: true),
          const SizedBox(height: 16),
          _buildFieldLabel('Longitude'),
          _buildModernField(viewModel.lngController, 'e.g. 71.72', Icons.gps_fixed_rounded, isNumber: true),
          const SizedBox(height: 32),
          Row(
            children: [
              if (viewModel.editingHubName != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      onPressed: () => viewModel.setEditingHub(null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: viewModel.isHubSaving ? null : () => viewModel.saveHub(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: viewModel.isHubSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(viewModel.editingHubName != null ? 'Update' : 'Save Hub', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListPanel(FirebaseService firebaseService, RoutePlanningViewModel viewModel) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('All Hubs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          StreamBuilder<List<HubModel>>(
            stream: firebaseService.getHubs(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
              final hubs = snapshot.data ?? [];
              if (hubs.isEmpty) return _buildEmptyState('No hubs defined.');

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: hubs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final hub = hubs[index];
                  return _HubCard(hub: hub, viewModel: viewModel);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HubCard extends StatefulWidget {
  final HubModel hub;
  final RoutePlanningViewModel viewModel;
  const _HubCard({required this.hub, required this.viewModel});

  @override
  State<_HubCard> createState() => _HubCardState();
}

class _HubCardState extends State<_HubCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isHovered ? AppColors.primaryNavy.withValues(alpha: 0.02) : AppColors.backgroundLight.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _isHovered ? AppColors.primaryNavy.withValues(alpha: 0.2) : AppColors.borderLight),
        ),
        child: Row(
          children: [
            AnimatedScale(
              scale: _isHovered ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.location_on_rounded, color: Colors.green.withValues(alpha: 0.7), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.hub.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _isHovered ? AppColors.primaryNavy : AppColors.textDark)),
                  Text('${widget.hub.latitude}, ${widget.hub.longitude}', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            _buildActionMenu(context, 
              onEdit: () => widget.viewModel.setEditingHub(widget.hub),
              onDelete: () => widget.viewModel.deleteHub(widget.hub.name),
              deleteMsg: 'Delete this hub?'
            ),
          ],
        ),
      ),
    );
  }
}

// --- Section B: Route Definition ---
class RouteDefinitionSection extends StatelessWidget {
  const RouteDefinitionSection({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<RoutePlanningViewModel>();
    final firebaseService = context.read<FirebaseService>();
    final isDesktop = AppResponsiveUtil.isDesktop(context);

    return StreamBuilder<List<HubModel>>(
      stream: firebaseService.getHubs(),
      builder: (context, hubSnapshot) {
        final hubs = hubSnapshot.data ?? [];
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Flex(
            direction: isDesktop ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: isDesktop ? 380 : double.infinity,
                child: _buildRouteForm(viewModel, hubs),
              ),
              if (isDesktop) const SizedBox(width: 24),
              if (!isDesktop) const SizedBox(height: 24),
              if (isDesktop)
                Expanded(child: _buildRouteList(viewModel, firebaseService))
              else
                _buildRouteList(viewModel, firebaseService),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRouteForm(RoutePlanningViewModel viewModel, List<HubModel> hubs) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Route Builder', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          _buildFieldLabel('Route Name'),
          _buildModernField(viewModel.routeNameController, 'e.g. Route A', Icons.edit_road_rounded),
          const SizedBox(height: 16),
          _buildFieldLabel('From'),
          _buildModernDropdown(viewModel.fromHub, hubs.map((h) => h.name).toList(), 'Start Hub', Icons.start_rounded, Colors.green, (v) => viewModel.setFromHub(v)),
          const SizedBox(height: 16),
          _buildFieldLabel('To'),
          _buildModernDropdown(viewModel.toHub, hubs.map((h) => h.name).toList(), 'Destination Hub', Icons.location_on_rounded, Colors.red, (v) => viewModel.setToHub(v)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: viewModel.isRouteSaving ? null : () => viewModel.saveRoute(),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: viewModel.isRouteSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(viewModel.editingRouteId != null ? 'Update Route' : 'Create Route', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteList(RoutePlanningViewModel viewModel, FirebaseService firebaseService) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Active Routes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          StreamBuilder<List<BusSchedule>>(
            stream: firebaseService.getBusSchedules(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
              final allSchedules = snapshot.data ?? [];
              // Show only master route templates (no date, no operatingDays, no specific departure time)
              final schedules = allSchedules.where((s) {
                final hasNoDate = s.date == null || s.date!.isEmpty;
                final hasNoOperatingDays = s.operatingDays == null || s.operatingDays!.isEmpty;
                final hasNoTime = s.departureTime == null ||
                    s.departureTime!.isEmpty ||
                    s.departureTime == 'TBA' ||
                    s.departureTime == 'Live';
                return hasNoDate && hasNoOperatingDays && hasNoTime;
              }).fold<List<BusSchedule>>([], (acc, s) {
                if (!acc.any((r) => r.route == s.route)) acc.add(s);
                return acc;
              });
              if (schedules.isEmpty) return _buildEmptyState('No routes defined.');

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: schedules.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final route = schedules[index];
                  return _RouteCard(route: route, viewModel: viewModel);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RouteCard extends StatefulWidget {
  final BusSchedule route;
  final RoutePlanningViewModel viewModel;
  const _RouteCard({required this.route, required this.viewModel});

  @override
  State<_RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends State<_RouteCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isHovered ? AppColors.primaryNavy.withValues(alpha: 0.02) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _isHovered ? AppColors.primaryNavy.withValues(alpha: 0.2) : AppColors.borderLight),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.route.route, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _isHovered ? AppColors.primaryNavy : AppColors.textDark)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(widget.route.from, style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600)),
                      Icon(Icons.arrow_right_alt, size: 16, color: AppColors.textSecondary),
                      Text(widget.route.to, style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            _buildActionMenu(context, 
              onEdit: () => widget.viewModel.setEditingRoute(widget.route),
              onDelete: () => widget.viewModel.deleteRoute(widget.route.id, widget.route.route),
              deleteMsg: 'Delete this route?'
            ),
          ],
        ),
      ),
    );
  }
}

// --- Section C: Polyline Uploader ---
class PolylineUploaderSection extends StatelessWidget {
  const PolylineUploaderSection({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<RoutePlanningViewModel>();
    final firebaseService = context.read<FirebaseService>();
    final isDesktop = AppResponsiveUtil.isDesktop(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Flex(
        direction: isDesktop ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isDesktop ? 380 : double.infinity,
            child: _buildPolylineForm(context, viewModel, firebaseService),
          ),
          if (isDesktop) const SizedBox(width: 24),
          if (!isDesktop) const SizedBox(height: 24),
          if (isDesktop)
            Expanded(child: _buildPolylineStatus(firebaseService))
          else
            _buildPolylineStatus(firebaseService),
        ],
      ),
    );
  }

  Widget _buildPolylineForm(BuildContext context, RoutePlanningViewModel viewModel, FirebaseService firebaseService) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Path Sync', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          _buildFieldLabel('Select Route'),
          StreamBuilder<List<BusSchedule>>(
            stream: firebaseService.getBusSchedules(),
            builder: (context, snapshot) {
              final allRoutes = snapshot.data ?? [];
              // Only show master route templates
              final masterRouteNames = allRoutes.where((s) {
                final hasNoDate = s.date == null || s.date!.isEmpty;
                final hasNoOperatingDays = s.operatingDays == null || s.operatingDays!.isEmpty;
                final hasNoTime = s.departureTime == null ||
                    s.departureTime!.isEmpty ||
                    s.departureTime == 'TBA' ||
                    s.departureTime == 'Live';
                return hasNoDate && hasNoOperatingDays && hasNoTime;
              }).map((s) => s.route).toSet().toList();
              return _buildModernDropdown(
                viewModel.selectedRouteForPolyline,
                masterRouteNames,
                'Route', Icons.alt_route_rounded, AppColors.primaryNavy, (v) => viewModel.setSelectedRouteForPolyline(v)
              );
            },
          ),
          const SizedBox(height: 16),
          _buildFieldLabel('Coordinates (JSON)'),
          Container(
            height: 120,
            decoration: BoxDecoration(color: AppColors.backgroundLight, borderRadius: BorderRadius.circular(12)),
            child: TextField(
              controller: viewModel.jsonController,
              maxLines: null,
              expands: true,
              style: GoogleFonts.firaCode(fontSize: 10),
              decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(12)),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: viewModel.isPolylineSaving
                  ? null
                  : () async {
                      try {
                        await viewModel.uploadPolyline();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Path synchronized successfully!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to sync path: ${e.toString().replaceAll("Exception: ", "")}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sync Path', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryNavy, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolylineStatus(FirebaseService firebaseService) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          StreamBuilder<Map<String, dynamic>>(
            stream: firebaseService.getPolylinesStatus(),
            builder: (context, polylineSnapshot) {
              final polylines = polylineSnapshot.data ?? {};
              return StreamBuilder<List<BusSchedule>>(
                stream: firebaseService.getBusSchedules(),
                builder: (context, routeSnapshot) {
                  final allRoutes = routeSnapshot.data ?? [];
                  // Only show master route templates
                  final routes = allRoutes.where((s) {
                    final hasNoDate = s.date == null || s.date!.isEmpty;
                    final hasNoOperatingDays = s.operatingDays == null || s.operatingDays!.isEmpty;
                    final hasNoTime = s.departureTime == null ||
                        s.departureTime!.isEmpty ||
                        s.departureTime == 'TBA' ||
                        s.departureTime == 'Live';
                    return hasNoDate && hasNoOperatingDays && hasNoTime;
                  }).fold<List<BusSchedule>>([], (acc, s) {
                    if (!acc.any((r) => r.route == s.route)) acc.add(s);
                    return acc;
                  });
                  if (routes.isEmpty) return _buildEmptyState('No routes.');

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: routes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final route = routes[index];
                      final routeName = route.route;
                      final hasPolyline = polylines.containsKey(routeName);

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: hasPolyline ? Colors.green.withValues(alpha: 0.05) : Colors.orange.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(hasPolyline ? Icons.check_circle : Icons.error_outline, color: hasPolyline ? Colors.green : Colors.orange, size: 18),
                            const SizedBox(width: 12),
                            Expanded(child: Text(routeName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                            Text(hasPolyline ? 'Live' : 'Missing', style: TextStyle(color: hasPolyline ? Colors.green : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

// --- Section E: Map Preview ---
class MapPreviewSection extends StatefulWidget {
  const MapPreviewSection({super.key});

  @override
  State<MapPreviewSection> createState() => _MapPreviewSectionState();
}

class _MapPreviewSectionState extends State<MapPreviewSection> {
  String? _selectedRoute;
  String? _lastFittedRoute;
  final MapController _mapController = MapController();

  void _fitAllPoints(List<HubModel> hubs, List<StopModel> stops, List<LatLng> polylinePoints) {
    final List<LatLng> allPoints = [];
    for (final hub in hubs) {
      allPoints.add(LatLng(hub.latitude, hub.longitude));
    }
    for (final stop in stops) {
      allPoints.add(LatLng(stop.latitude, stop.longitude));
    }
    allPoints.addAll(polylinePoints);

    if (allPoints.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final bounds = LatLngBounds.fromPoints(allPoints);
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(50),
            ),
          );
        } catch (e) {
          debugPrint("Error fitting bounds: $e");
        }
      }
    });
  }

  Widget _buildMapButton({required IconData icon, required VoidCallback onPressed, bool isMobile = false}) {
    return Container(
      width: isMobile ? 32 : 40,
      height: isMobile ? 32 : 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: AppColors.primaryNavy, size: isMobile ? 16 : 20),
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();
    final isMobile = AppResponsiveUtil.isMobile(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Route selector
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primaryNavy.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.map_rounded, color: AppColors.primaryNavy, size: 18),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Route Map Preview', 
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<List<BusSchedule>>(
                        stream: firebaseService.getBusSchedules(),
                        builder: (context, snapshot) {
                          final allRoutes = snapshot.data ?? [];
                          // Only show master route templates
                          final uniqueRouteNames = allRoutes.where((s) {
                            final hasNoDate = s.date == null || s.date!.isEmpty;
                            final hasNoOperatingDays = s.operatingDays == null || s.operatingDays!.isEmpty;
                            final hasNoTime = s.departureTime == null ||
                                s.departureTime!.isEmpty ||
                                s.departureTime == 'TBA' ||
                                s.departureTime == 'Live';
                            return hasNoDate && hasNoOperatingDays && hasNoTime;
                          }).map((r) => r.route).toSet().toList();

                          if (_selectedRoute != null && !uniqueRouteNames.contains(_selectedRoute)) {
                            SchedulerBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _selectedRoute = uniqueRouteNames.isNotEmpty ? uniqueRouteNames.first : null);
                            });
                          } else if (_selectedRoute == null && uniqueRouteNames.isNotEmpty) {
                            SchedulerBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _selectedRoute = uniqueRouteNames.first);
                            });
                          }

                          String? safeValue = _selectedRoute;
                          if (safeValue != null && !uniqueRouteNames.contains(safeValue)) {
                            safeValue = null;
                          }

                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: safeValue,
                                isExpanded: true,
                                hint: Text(uniqueRouteNames.isEmpty ? 'No routes' : 'Select route', style: const TextStyle(fontSize: 13)),
                                items: uniqueRouteNames.map((name) => DropdownMenuItem(value: name, child: Text(name, style: const TextStyle(fontSize: 13)))).toList(),
                                onChanged: uniqueRouteNames.isEmpty ? null : (v) => setState(() => _selectedRoute = v),
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryNavy.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.map_rounded, color: AppColors.primaryNavy, size: 20),
                      ),
                      const SizedBox(width: 16),
                      const Text('Route Map Preview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      // Route dropdown
                      StreamBuilder<List<BusSchedule>>(
                        stream: firebaseService.getBusSchedules(),
                        builder: (context, snapshot) {
                          final allRoutes = snapshot.data ?? [];
                          // Only show master route templates
                          final uniqueRouteNames = allRoutes.where((s) {
                            final hasNoDate = s.date == null || s.date!.isEmpty;
                            final hasNoOperatingDays = s.operatingDays == null || s.operatingDays!.isEmpty;
                            final hasNoTime = s.departureTime == null ||
                                s.departureTime!.isEmpty ||
                                s.departureTime == 'TBA' ||
                                s.departureTime == 'Live';
                            return hasNoDate && hasNoOperatingDays && hasNoTime;
                          }).map((r) => r.route).toSet().toList();

                          if (_selectedRoute != null && !uniqueRouteNames.contains(_selectedRoute)) {
                            SchedulerBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _selectedRoute = uniqueRouteNames.isNotEmpty ? uniqueRouteNames.first : null);
                            });
                          } else if (_selectedRoute == null && uniqueRouteNames.isNotEmpty) {
                            SchedulerBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _selectedRoute = uniqueRouteNames.first);
                            });
                          }

                          String? safeValue = _selectedRoute;
                          if (safeValue != null && !uniqueRouteNames.contains(safeValue)) {
                            safeValue = null;
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: safeValue,
                                hint: Text(uniqueRouteNames.isEmpty ? 'No routes' : 'Select route', style: const TextStyle(fontSize: 13)),
                                items: uniqueRouteNames.map((name) => DropdownMenuItem(value: name, child: Text(name, style: const TextStyle(fontSize: 13)))).toList(),
                                onChanged: uniqueRouteNames.isEmpty ? null : (v) => setState(() => _selectedRoute = v),
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),

          // Map canvas
          SizedBox(
            height: 500,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.borderLight),
              ),
              clipBehavior: Clip.antiAlias,
              child: _selectedRoute == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined, size: 64, color: AppColors.textSecondary),
                          SizedBox(height: 16),
                          Text('Select a route above to preview its map', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                        ],
                      ),
                    )
                  : StreamBuilder<List<BusSchedule>>(
                      stream: firebaseService.getBusSchedules(),
                      builder: (context, routeSnapshot) {
                        return StreamBuilder<List<HubModel>>(
                          stream: firebaseService.getHubs(),
                          builder: (context, hubSnapshot) {
                            return StreamBuilder<List<StopModel>>(
                              stream: firebaseService.getStops(),
                              builder: (context, stopSnapshot) {
                                return StreamBuilder<Map<String, dynamic>>(
                                  stream: firebaseService.getPolylinesStatus(),
                                  builder: (context, polylineSnapshot) {
                                    final hubs = hubSnapshot.data ?? [];
                                    final allStops = stopSnapshot.data ?? [];
                                    final routeStops = allStops.where((s) => s.route == _selectedRoute).toList();
                                    final polylineData = polylineSnapshot.data ?? {};

                                // Parse polyline coordinates for selected route
                                List<LatLng> polylineLatLngs = [];
                                if (_selectedRoute != null && polylineData.containsKey(_selectedRoute)) {
                                  final rawCoords = polylineData[_selectedRoute];
                                  if (rawCoords is List) {
                                    for (final coord in rawCoords) {
                                      if (coord is List && coord.length >= 2) {
                                        final lat = (coord[0] as num).toDouble();
                                        final lng = (coord[1] as num).toDouble();
                                        polylineLatLngs.add(LatLng(lat, lng));
                                      } else if (coord is Map) {
                                        final lat = (coord['latitude'] ?? coord['lat'] ?? 0) as num;
                                        final lng = (coord['longitude'] ?? coord['lng'] ?? 0) as num;
                                        polylineLatLngs.add(LatLng(lat.toDouble(), lng.toDouble()));
                                      }
                                    }
                                  }
                                }

                                // Trigger fit camera once when route changes or loaded
                                // Only use hubs that match this route's from/to
                                final selectedScheduleForFit = (routeSnapshot.data ?? [])
                                    .where((r) => r.route == _selectedRoute)
                                    .firstOrNull;
                                final fromHubName = selectedScheduleForFit?.from.trim().toLowerCase() ?? '';
                                final toHubName = selectedScheduleForFit?.to.trim().toLowerCase() ?? '';
                                final routeHubs = hubs.where((h) {
                                  final n = h.name.trim().toLowerCase();
                                  return n == fromHubName || n == toHubName;
                                }).toList();

                                if (_selectedRoute != _lastFittedRoute && (routeHubs.isNotEmpty || routeStops.isNotEmpty || polylineLatLngs.isNotEmpty)) {
                                  _lastFittedRoute = _selectedRoute;
                                  _fitAllPoints(routeHubs, routeStops, polylineLatLngs);
                                }

                                if (hubs.isEmpty && routeStops.isEmpty && polylineLatLngs.isEmpty) {
                                  return Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.info_outline_rounded, size: 48, color: AppColors.textSecondary),
                                        SizedBox(height: 12),
                                        Text('No data available for this route.', style: TextStyle(color: AppColors.textSecondary)),
                                        SizedBox(height: 4),
                                        Text('Add hubs, stops, and upload a polyline path first.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                      ],
                                    ),
                                  );
                                }

                                return Stack(
                                  children: [
                                    FlutterMap(
                                      mapController: _mapController,
                                      options: const MapOptions(
                                        initialCenter: LatLng(29.3780, 71.7575), // Baghdad Campus default
                                        initialZoom: 13,
                                      ),
                                      children: [
                                        TileLayer(
                                          urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                                          subdomains: const ['a', 'b', 'c', 'd'],
                                        ),
                                        if (polylineLatLngs.isNotEmpty)
                                          PolylineLayer(
                                            polylines: [
                                              Polyline(
                                                points: polylineLatLngs,
                                                color: const Color(0xFF1A237E),
                                                strokeWidth: 5.0,
                                                borderColor: const Color(0xFFE8EAF6),
                                                borderStrokeWidth: 2.0,
                                              ),
                                            ],
                                          ),
                                        MarkerLayer(
                                          markers: [
                                            // Stops markers
                                            ...routeStops.map((stop) {
                                              return Marker(
                                                point: LatLng(stop.latitude, stop.longitude),
                                                width: 120,
                                                height: 50,
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius: BorderRadius.circular(12),
                                                        border: Border.all(color: Colors.orange),
                                                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                                                      ),
                                                      child: Text(
                                                        stop.name,
                                                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    const Icon(Icons.radio_button_checked, color: Colors.orange, size: 16),
                                                  ],
                                                ),
                                              );
                                            }),
                                         // Hubs markers — only for selected route
                                            ...() {
                                              if (_selectedRoute == null) return <Marker>[];

                                              // Find the schedule to get exact from/to hub names
                                              final selectedScheduleObj = (routeSnapshot.data ?? [])
                                                  .where((r) => r.route == _selectedRoute)
                                                  .firstOrNull;

                                              final fromHub = selectedScheduleObj?.from.trim().toLowerCase() ?? '';
                                              final toHub = selectedScheduleObj?.to.trim().toLowerCase() ?? '';

                                              return hubs.where((hub) {
                                                final n = hub.name.trim().toLowerCase();
                                                return n == fromHub || n == toHub;
                                              }).map((hub) {
                                                final hubNameLower = hub.name.trim().toLowerCase();
                                                final isStart = hubNameLower == fromHub;
                                                final markerColor = isStart ? Colors.green : Colors.red;

                                                return Marker(
                                                  point: LatLng(hub.latitude, hub.longitude),
                                                  width: 130,
                                                  height: 70,
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                        decoration: BoxDecoration(
                                                          color: markerColor,
                                                          borderRadius: BorderRadius.circular(12),
                                                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(isStart ? Icons.trip_origin : Icons.location_on, color: Colors.white, size: 12),
                                                            const SizedBox(width: 4),
                                                            Flexible(
                                                              child: Text(
                                                                hub.name,
                                                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Icon(Icons.location_on, color: markerColor, size: 30),
                                                    ],
                                                  ),
                                                );
                                              }).toList();
                                            }(),
                                          ],
                                        ),
                                      ],
                                    ),
                                    // Control Buttons
                                    Positioned(
                                      bottom: isMobile ? 10 : 16,
                                      left: isMobile ? 10 : 16,
                                      child: Column(
                                        children: [
                                          _buildMapButton(
                                            icon: Icons.add,
                                            isMobile: isMobile,
                                            onPressed: () {
                                              _mapController.move(
                                                _mapController.camera.center,
                                                _mapController.camera.zoom + 1,
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 8),
                                          _buildMapButton(
                                            icon: Icons.remove,
                                            isMobile: isMobile,
                                            onPressed: () {
                                              _mapController.move(
                                                _mapController.camera.center,
                                                _mapController.camera.zoom - 1,
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 8),
                                          _buildMapButton(
                                            icon: Icons.center_focus_strong,
                                            isMobile: isMobile,
                                            onPressed: () => _fitAllPoints(hubs, routeStops, polylineLatLngs),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Legend
                                    Positioned(
                                      bottom: isMobile ? 10 : 16,
                                      right: isMobile ? 10 : 16,
                                      child: Container(
                                        padding: EdgeInsets.all(isMobile ? 8 : 12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.95),
                                          borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
                                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Legend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: isMobile ? 10 : 12, color: AppColors.textDark)),
                                            SizedBox(height: isMobile ? 4 : 8),
                                            _buildLegendItem(AppColors.accentAmber, Icons.circle, 'Hub / Campus', isMobile),
                                            SizedBox(height: isMobile ? 2 : 4),
                                            _buildLegendItem(Colors.orange, Icons.radio_button_checked, 'Bus Stop', isMobile),
                                            SizedBox(height: isMobile ? 2 : 4),
                                            _buildLegendItem(const Color(0xFF1A237E), Icons.remove, 'Route Path', isMobile),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Route name badge
                                    Positioned(
                                      top: 16,
                                      left: 16,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryNavy,
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 14),
                                            const SizedBox(width: 6),
                                            Text(
                                              _selectedRoute ?? '',
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Stats overlay
                                    Positioned(
                                      top: 16,
                                      right: 16,
                                      child: Container(
                                        padding: EdgeInsets.all(isMobile ? 8 : 12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.95),
                                          borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
                                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _buildStatRow(Icons.location_city_rounded, '${hubs.length} Hubs', Colors.blue, isMobile),
                                            SizedBox(height: isMobile ? 2 : 4),
                                            _buildStatRow(Icons.radio_button_checked, '${routeStops.length} Stops', Colors.orange, isMobile),
                                            SizedBox(height: isMobile ? 2 : 4),
                                            _buildStatRow(
                                              polylineLatLngs.isEmpty ? Icons.warning_amber_rounded : Icons.polyline_rounded,
                                              polylineLatLngs.isEmpty ? (isMobile ? 'No path' : 'No path uploaded') : '${polylineLatLngs.length} coords',
                                              polylineLatLngs.isEmpty ? Colors.orange : Colors.green,
                                              isMobile,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, IconData icon, String label, bool isMobile) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: isMobile ? 12 : 14),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: isMobile ? 9 : 11, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildStatRow(IconData icon, String label, Color color, bool isMobile) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: isMobile ? 12 : 14),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: isMobile ? 9 : 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// Grid background painter
class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD1D5DB).withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    const gridSize = 40.0;
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Route map painter — projects lat/lng to canvas and draws polyline + hubs + stops
class RouteMapPainter extends CustomPainter {
  final List<HubModel> hubs;
  final List<StopModel> stops;
  final List<List<double>> polylinePoints;

  const RouteMapPainter({
    required this.hubs,
    required this.stops,
    required this.polylinePoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 72.0;

    // Gather all lat/lng values to compute bounding box
    final List<double> lats = [];
    final List<double> lngs = [];

    for (final hub in hubs) {
      lats.add(hub.latitude);
      lngs.add(hub.longitude);
    }
    for (final stop in stops) {
      lats.add(stop.latitude);
      lngs.add(stop.longitude);
    }
    for (final pt in polylinePoints) {
      lats.add(pt[0]);
      lngs.add(pt[1]);
    }

    if (lats.isEmpty || lngs.isEmpty) return;

    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min);
    final maxLng = lngs.reduce(math.max);

    // Projection function: geo coord → canvas Offset
    Offset project(double lat, double lng) {
      final latRange = maxLat - minLat;
      final lngRange = maxLng - minLng;

      if (latRange == 0 && lngRange == 0) {
        return Offset(size.width / 2, size.height / 2);
      }

      final drawW = size.width - padding * 2;
      final drawH = size.height - padding * 2;

      double x, y;
      if (lngRange == 0) {
        x = size.width / 2;
      } else {
        x = padding + ((lng - minLng) / lngRange) * drawW;
      }
      if (latRange == 0) {
        y = size.height / 2;
      } else {
        // Flip y: higher lat = top of screen
        y = padding + ((maxLat - lat) / latRange) * drawH;
      }
      return Offset(x, y);
    }

    // 1. Draw polyline path
    if (polylinePoints.length > 1) {
      final shadowPaint = Paint()
        ..color = const Color(0xFF1A237E).withValues(alpha: 0.15)
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final linePaint = Paint()
        ..color = const Color(0xFF1A237E)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = ui.Path();
      final first = project(polylinePoints[0][0], polylinePoints[0][1]);
      path.moveTo(first.dx, first.dy);
      for (int i = 1; i < polylinePoints.length; i++) {
        final pt = project(polylinePoints[i][0], polylinePoints[i][1]);
        path.lineTo(pt.dx, pt.dy);
      }

      canvas.drawPath(path, shadowPaint);
      canvas.drawPath(path, linePaint);

      // Draw direction arrows along the path
      final arrowPaint = Paint()
        ..color = const Color(0xFF1A237E).withValues(alpha: 0.7)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      final step = math.max(1, polylinePoints.length ~/ 6);
      for (int i = step; i < polylinePoints.length - 1; i += step) {
        final p1 = project(polylinePoints[i - 1][0], polylinePoints[i - 1][1]);
        final p2 = project(polylinePoints[i][0], polylinePoints[i][1]);
        _drawArrow(canvas, p1, p2, arrowPaint);
      }
    }

    // 2. Draw stops
    for (final stop in stops) {
      final pos = project(stop.latitude, stop.longitude);

      final outerPaint = Paint()..color = Colors.white;
      final innerPaint = Paint()..color = Colors.orange;
      final borderPaint = Paint()
        ..color = Colors.orange.withValues(alpha: 0.6)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(pos, 9, outerPaint);
      canvas.drawCircle(pos, 5, innerPaint);
      canvas.drawCircle(pos, 9, borderPaint);

      // Stop label
      _drawLabel(canvas, pos, stop.name, const Offset(0, -18), 9, Colors.orange.shade700, Colors.orange.withValues(alpha: 0.1));
    }

    // 3. Draw hubs (larger markers with pin shape)
    for (final hub in hubs) {
      final pos = project(hub.latitude, hub.longitude);

      // Pin shadow
      final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.12);
      canvas.drawCircle(pos.translate(2, 3), 14, shadowPaint);

      // Outer white ring
      final outerPaint = Paint()..color = Colors.white;
      canvas.drawCircle(pos, 14, outerPaint);

      // Filled hub circle
      final hubPaint = Paint()..color = AppColors.accentAmber;
      canvas.drawCircle(pos, 11, hubPaint);

      // Icon: small bus icon (dot)
      final dotPaint = Paint()..color = Colors.white;
      canvas.drawCircle(pos, 4, dotPaint);

      // Hub label
      _drawLabel(canvas, pos, hub.name, const Offset(0, 22), 10, const Color(0xFF1A237E), const Color(0xFFE8EAF6));
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Paint paint) {
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 10) return;

    final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
    final angle = math.atan2(dy, dx);
    const arrowSize = 8.0;

    final path = ui.Path();
    path.moveTo(mid.dx - arrowSize * math.cos(angle - 0.5), mid.dy - arrowSize * math.sin(angle - 0.5));
    path.lineTo(mid.dx + arrowSize * math.cos(angle), mid.dy + arrowSize * math.sin(angle));
    path.lineTo(mid.dx - arrowSize * math.cos(angle + 0.5), mid.dy - arrowSize * math.sin(angle + 0.5));
    canvas.drawPath(path, paint);
  }

  void _drawLabel(Canvas canvas, Offset pos, String text, Offset labelOffset, double fontSize, Color textColor, Color bgColor) {
    const maxLen = 18;
    final displayText = text.length > maxLen ? '${text.substring(0, maxLen)}…' : text;

    final textPainter = TextPainter(
      text: TextSpan(
        text: displayText,
        style: TextStyle(color: textColor, fontSize: fontSize, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelPos = pos.translate(labelOffset.dx - textPainter.width / 2, labelOffset.dy);
    final bgRect = Rect.fromLTWH(labelPos.dx - 4, labelPos.dy - 2, textPainter.width + 8, textPainter.height + 4);
    canvas.drawRRect(RRect.fromRectAndRadius(bgRect, const Radius.circular(4)), Paint()..color = bgColor);
    textPainter.paint(canvas, labelPos);
  }

  @override
  bool shouldRepaint(covariant RouteMapPainter oldDelegate) =>
      oldDelegate.hubs != hubs ||
      oldDelegate.stops != stops ||
      oldDelegate.polylinePoints != polylinePoints;
}

// --- Section D: Stops Manager ---
class StopsManagerSection extends StatelessWidget {
  const StopsManagerSection({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<RoutePlanningViewModel>();
    final firebaseService = context.read<FirebaseService>();
    final isDesktop = AppResponsiveUtil.isDesktop(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Flex(
        direction: isDesktop ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isDesktop ? 380 : double.infinity,
            child: _buildStopForm(viewModel, firebaseService),
          ),
          if (isDesktop) const SizedBox(width: 24),
          if (!isDesktop) const SizedBox(height: 24),
          if (isDesktop)
            Expanded(child: _buildStopList(firebaseService, viewModel))
          else
            _buildStopList(firebaseService, viewModel),
        ],
      ),
    );
  }

  Widget _buildStopForm(RoutePlanningViewModel viewModel, FirebaseService firebaseService) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            viewModel.editingStopId != null ? 'Edit Stop' : 'Add New Stop',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          _buildFieldLabel('Stop Name'),
          _buildModernField(viewModel.stopNameController, 'e.g. Near Library', Icons.location_city_rounded),
          const SizedBox(height: 16),
          _buildFieldLabel('Select Route'),
          StreamBuilder<List<BusSchedule>>(
            stream: firebaseService.getBusSchedules(),
            builder: (context, snapshot) {
              final allRoutes = snapshot.data ?? [];
              // Only show master route templates
              final masterRouteNames = allRoutes.where((s) {
                final hasNoDate = s.date == null || s.date!.isEmpty;
                final hasNoOperatingDays = s.operatingDays == null || s.operatingDays!.isEmpty;
                final hasNoTime = s.departureTime == null ||
                    s.departureTime!.isEmpty ||
                    s.departureTime == 'TBA' ||
                    s.departureTime == 'Live';
                return hasNoDate && hasNoOperatingDays && hasNoTime;
              }).map((s) => s.route).toSet().toList();
              return _buildModernDropdown(
                viewModel.selectedRouteForStop,
                masterRouteNames,
                'Route', Icons.alt_route_rounded, AppColors.primaryNavy, (v) => viewModel.setSelectedRouteForStop(v)
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Latitude'),
                    _buildModernField(viewModel.stopLatController, '0.00', Icons.gps_fixed_rounded, isNumber: true),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Longitude'),
                    _buildModernField(viewModel.stopLngController, '0.00', Icons.gps_fixed_rounded, isNumber: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              if (viewModel.editingStopId != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      onPressed: () => viewModel.setEditingStop(null),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: viewModel.isStopSaving ? null : () => viewModel.saveStop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: viewModel.isStopSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(viewModel.editingStopId != null ? 'Update Stop' : 'Save Stop', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStopList(FirebaseService firebaseService, RoutePlanningViewModel viewModel) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('All Stops', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          StreamBuilder<List<StopModel>>(
            stream: firebaseService.getStops(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
              final stops = snapshot.data ?? [];
              if (stops.isEmpty) return _buildEmptyState('No stops defined.');

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: stops.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final stop = stops[index];
                  return _StopCard(stop: stop, viewModel: viewModel);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StopCard extends StatefulWidget {
  final StopModel stop;
  final RoutePlanningViewModel viewModel;
  const _StopCard({required this.stop, required this.viewModel});

  @override
  State<_StopCard> createState() => _StopCardState();
}

class _StopCardState extends State<_StopCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isHovered ? AppColors.primaryNavy.withValues(alpha: 0.02) : AppColors.backgroundLight.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _isHovered ? AppColors.primaryNavy.withValues(alpha: 0.2) : AppColors.borderLight),
        ),
        child: Row(
          children: [
            AnimatedScale(
              scale: _isHovered ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.radio_button_checked_rounded, color: Colors.grey, size: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.stop.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _isHovered ? AppColors.primaryNavy : AppColors.textDark)),
                  Text('Route: ${widget.stop.route}', style: TextStyle(color: AppColors.primaryNavy, fontSize: 11, fontWeight: FontWeight.w600)),
                  Text('${widget.stop.latitude}, ${widget.stop.longitude}', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ],
              ),
            ),
            _buildActionMenu(context, 
              onEdit: () => widget.viewModel.setEditingStop(widget.stop),
              onDelete: () => widget.viewModel.deleteStop(widget.stop.id),
              deleteMsg: 'Delete this stop?'
            ),
          ],
        ),
      ),
    );
  }
}

// --- SHARED HELPER WIDGETS ---

Widget _buildFieldLabel(String label) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6.0),
    child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textDark)),
  );
}

Widget _buildModernField(TextEditingController controller, String hint, IconData icon, {bool isNumber = false, TextInputAction action = TextInputAction.next}) {
  return TextField(
    controller: controller,
    keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    textInputAction: action,
    style: const TextStyle(fontSize: 13),
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.primaryNavy, size: 18),
      filled: true,
      fillColor: AppColors.backgroundLight,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
}

Widget _buildModernDropdown(String? value, List<String> items, String hint, IconData icon, Color iconColor, Function(String?) onChanged) {
  // Deduplicate items to prevent duplicate dropdown item assertion crash
  final uniqueItems = items.toSet().toList();
  
  // Safe-guard value parameter
  String? safeValue = value;
  if (safeValue != null && !uniqueItems.contains(safeValue)) {
    safeValue = null;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: AppColors.backgroundLight, borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: safeValue,
        isExpanded: true,
        hint: Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 10),
            Text(hint, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary, size: 18),
        items: uniqueItems.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
        onChanged: onChanged,
      ),
    ),
  );
}

Widget _buildActionMenu(BuildContext context, {required VoidCallback onEdit, required VoidCallback onDelete, required String deleteMsg}) {
  return PopupMenuButton<String>(
    onSelected: (v) {
      if (v == 'edit') onEdit();
      if (v == 'delete') {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm'),
            content: Text(deleteMsg),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('No')),
              TextButton(onPressed: () { onDelete(); Navigator.pop(context); }, child: const Text('Yes')),
            ],
          ),
        );
      }
    },
    icon: Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
    itemBuilder: (context) => [
      const PopupMenuItem(value: 'edit', child: Text('Edit')),
      const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
    ],
  );
}

Widget _buildEmptyState(String msg) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(msg, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    ),
  );
}