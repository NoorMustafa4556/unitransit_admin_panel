import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:unitransit_admin/core/constants/app_colors.dart';
import 'package:unitransit_admin/core/utils/responsive_util.dart';
import 'package:unitransit_admin/models/bus_schedule_model.dart';
import 'package:unitransit_admin/core/utils/animations.dart';
import 'package:unitransit_admin/view_models/fleet_operations_view_model.dart';
import 'package:unitransit_admin/view_models/dashboard_view_model.dart';
import 'package:unitransit_admin/view_models/login_view_model.dart';


class FleetOperationsScreen extends StatefulWidget {
  const FleetOperationsScreen({super.key});

  @override
  State<FleetOperationsScreen> createState() => _FleetOperationsScreenState();
}

class _FleetOperationsScreenState extends State<FleetOperationsScreen>
    with TickerProviderStateMixin {
  final _searchController = TextEditingController();
  final MapController _mapController = MapController();
  final ScrollController _calendarScrollController = ScrollController();
  final LatLng _defaultCenter = const LatLng(
    29.378047555871532,
    71.75750718286565,
  );

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      context.read<FleetOperationsViewModel>().updateSearchQuery(
        _searchController.text,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToSelectedDate(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _calendarScrollController.dispose();
    super.dispose();
  }

  void _scrollToSelectedDate() {
    if (_calendarScrollController.hasClients) {
      final vm = context.read<FleetOperationsViewModel>();
      final index = vm.selectedDate.day - 1;
      _calendarScrollController.animateTo(
        index * 58.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _locateBus(Map<String, dynamic> bus) {
    final lat = (bus['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (bus['longitude'] as num?)?.toDouble() ?? 0.0;
    if (lat != 0.0 && lng != 0.0) {
      context.read<FleetOperationsViewModel>().selectBus(bus['id']);
      _animatedMapMove(LatLng(lat, lng), 16.0);
    }
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final latTween = Tween<double>(
      begin: _mapController.camera.center.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: _mapController.camera.center.longitude,
      end: destLocation.longitude,
    );
    final zoomTween = Tween<double>(
      begin: _mapController.camera.zoom,
      end: destZoom,
    );
    final controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.fastOutSlowIn,
    );
    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });
    controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final loginVM = context.read<LoginViewModel>();
    final vm = context.watch<FleetOperationsViewModel>();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      vm.setSuperAdmin(loginVM.isSuperAdmin);
    });

    final isMobile = AppResponsiveUtil.isMobile(context);
    final selectedBus = vm.selectedBus;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FadeInSlide(
        duration: const Duration(milliseconds: 600),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header details
              const SizedBox(height: 16),
              if (isMobile) ...[
                FadeInSlide(
                  direction: FadeInDirection.bottomToTop,
                  delay: const Duration(milliseconds: 100),
                  child: _buildStatsBadges(vm),
                ),
                const SizedBox(height: 16),
              ],

              _buildCalendarSection(vm),
              const SizedBox(height: 16),

              // Split View layout
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Directory List Side (Left Panel)
                  if (!isMobile)
                    FadeInSlide(
                      direction: FadeInDirection.leftToRight,
                      delay: const Duration(milliseconds: 200),
                      child: SizedBox(
                        width: 380,
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: AppColors.borderLight),
                          ),
                          color: AppColors.cardWhite,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: _buildDirectoryList(vm),
                          ),
                        ),
                      ),
                    ),
                  if (!isMobile) const SizedBox(width: 20),

                  // Map & Mobile Toggle Stack Side (Right Panel)
                  Expanded(
                    child: FadeInSlide(
                      direction: FadeInDirection.rightToLeft,
                      delay: const Duration(milliseconds: 300),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          height:
                              600, // Fixed height for map to allow page scrolling
                          decoration: BoxDecoration(
                            color: AppColors.cardWhite,
                            border: Border.all(color: AppColors.borderLight),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Stack(
                            children: [
                              // The Interactive Map
                              FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: _defaultCenter,
                                  initialZoom: 13,
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                                    subdomains: const ['a', 'b', 'c', 'd'],
                                  ),
                                  PolylineLayer(
                                    polylines: _buildMapPolylines(vm),
                                  ),
                                  MarkerLayer(markers: _buildMapMarkers(vm)),
                                ],
                              ),

                              // Map Controls overlay
                              Positioned(
                                right: 16,
                                bottom: 16,
                                child: Column(
                                  children: [
                                    _buildMapButton(
                                      icon: Icons.add,
                                      onPressed:
                                          () => _mapController.move(
                                            _mapController.camera.center,
                                            _mapController.camera.zoom + 1,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildMapButton(
                                      icon: Icons.remove,
                                      onPressed:
                                          () => _mapController.move(
                                            _mapController.camera.center,
                                            _mapController.camera.zoom - 1,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildMapButton(
                                      icon: Icons.my_location,
                                      onPressed:
                                          () => _animatedMapMove(
                                            _defaultCenter,
                                            13.5,
                                          ),
                                    ),
                                  ],
                                ),
                              ),

                              // Selected Bus Information Card popup overlay
                              if (selectedBus != null && selectedBus.isNotEmpty)
                                Positioned(
                                  left: 16,
                                  bottom: 16,
                                  right: isMobile ? 80 : 16,
                                  child: _buildSelectedBusDetailsCard(
                                    selectedBus,
                                    vm,
                                  ),
                                ),

                              // Mobile Drawer/Directory Toggle
                              if (isMobile)
                                Positioned(
                                  left: 16,
                                  top: 16,
                                  child: FloatingActionButton.small(
                                    backgroundColor: AppColors.primaryNavy,
                                    foregroundColor: Colors.white,
                                    child: const Icon(Icons.menu),
                                    onPressed: () {
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder:
                                            (
                                              context,
                                            ) => DraggableScrollableSheet(
                                              initialChildSize: 0.85,
                                              minChildSize: 0.5,
                                              maxChildSize: 0.95,
                                              builder:
                                                  (
                                                    context,
                                                    scrollController,
                                                  ) => Container(
                                                    decoration: BoxDecoration(
                                                      color:
                                                          AppColors
                                                              .backgroundLight,
                                                      borderRadius:
                                                          BorderRadius.vertical(
                                                            top:
                                                                Radius.circular(
                                                                  24,
                                                                ),
                                                          ),
                                                    ),
                                                    padding:
                                                        const EdgeInsets.all(
                                                          16,
                                                        ),
                                                    child: Column(
                                                      children: [
                                                        Container(
                                                          width: 40,
                                                          height: 5,
                                                          decoration: BoxDecoration(
                                                            color:
                                                                Colors
                                                                    .grey[300],
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  10,
                                                                ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 16,
                                                        ),
                                                        Expanded(
                                                          child:
                                                              _buildDirectoryList(
                                                                vm,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                            ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsBadges(FleetOperationsViewModel vm) {
    final activeCount = vm.activeCount;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCounterChip('Active Now', activeCount.toString(), Colors.green),
        const SizedBox(width: 12),
        _buildCounterChip('System Status', 'Online', AppColors.primaryNavy),
      ],
    );
  }

  Widget _buildCounterChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return FloatingActionButton.small(
      heroTag: null,
      backgroundColor: Colors.white,
      foregroundColor: AppColors.primaryNavy,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onPressed: onPressed,
      child: Icon(icon, size: 20),
    );
  }

  Widget _buildDirectoryList(FleetOperationsViewModel vm) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search text input
        TextField(
          controller: _searchController,
          style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'Search active buses...',
            prefixIcon: Icon(
              Icons.search_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.borderLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primaryNavy),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildScheduleProgressWidget(vm),
        const SizedBox(height: 12),

        // Quick Gender Filters
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children:
                ['All', 'Boys', 'Girls', 'Combined'].map((gender) {
                  final isSelected = vm.selectedGenderFilter == gender;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        gender,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              isSelected
                                  ? Colors.white
                                  : AppColors.textSecondary,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: AppColors.primaryNavy,
                      backgroundColor: const Color(0xFFF1F5F9),
                      showCheckmark: false,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color:
                              isSelected
                                  ? AppColors.primaryNavy
                                  : Colors.transparent,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          vm.setGenderFilter(gender);
                        }
                      },
                    ),
                  );
                }).toList(),
          ),
        ),
        const SizedBox(height: 8),

        // Route Filter
        _buildFilterDropdown(
          icon: Icons.route_rounded,
          label: 'Route',
          value: vm.selectedRouteFilter,
          items: vm.uniqueRoutes,
          onChanged: (val) {
            vm.setRouteFilter(val ?? 'All');
          },
        ),
        const SizedBox(height: 6),

        // Bus Number Filter
        _buildFilterDropdown(
          icon: Icons.directions_bus_rounded,
          label: 'Bus',
          value: vm.selectedBusNumberFilter,
          items: vm.uniqueBusNumbers,
          onChanged: (val) {
            vm.setBusNumberFilter(val ?? 'All');
          },
        ),
        const SizedBox(height: 16),

        // Bus listings
        vm.isLoading
            ? Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(color: AppColors.primaryNavy),
              ),
            )
            : vm.filteredBuses.isEmpty
            ? _buildEmptyListState(vm)
            : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: vm.filteredBuses.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final bus = vm.filteredBuses[index];
                final isSelected = vm.selectedBusId == bus['id'];
                final speed = (bus['speed'] as num?)?.toDouble() ?? 0.0;
                final lastUpdated =
                    bus['lastUpdated'] != null
                        ? DateTime.fromMillisecondsSinceEpoch(
                          bus['lastUpdated'] as int,
                        )
                        : DateTime.now();

                return _BusListItem(
                  bus: bus,
                  isSelected: isSelected,
                  speed: speed,
                  lastUpdated: lastUpdated,
                  matchedSchedule: vm.getMatchingSchedule(bus),
                  onTap: () => _locateBus(bus),
                );
              },
            ),
      ],
    );
  }

  Widget _buildEmptyListState(FleetOperationsViewModel vm) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.directions_bus_outlined,
            size: 48,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 12),
          Text(
            'No active buses found.',
            style: GoogleFonts.poppins(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (vm.hasActiveFilters)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: () {
                  _searchController.clear();
                  vm.clearAllFilters();
                },
                icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                label: Text(
                  'Clear all filters',
                  style: GoogleFonts.poppins(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required IconData icon,
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color:
            value != 'All'
                ? AppColors.primaryNavy.withValues(alpha: 0.06)
                : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              value != 'All'
                  ? AppColors.primaryNavy.withValues(alpha: 0.3)
                  : AppColors.borderLight,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 15,
            color:
                value != 'All'
                    ? AppColors.primaryNavy
                    : AppColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            '$label:',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: items.contains(value) ? value : 'All',
                isExpanded: true,
                isDense: true,
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color:
                      value != 'All'
                          ? AppColors.primaryNavy
                          : AppColors.textDark,
                ),
                items:
                    items
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(
                              item,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
          if (value != 'All')
            GestureDetector(
              onTap: () => onChanged('All'),
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectedBusDetailsCard(
    Map<String, dynamic> bus,
    FleetOperationsViewModel vm,
  ) {
    final speed = (bus['speed'] as num?)?.toDouble() ?? 0.0;
    final plate = bus['plateNumber']?.toString() ?? 'N/A';
    final remainingTime = bus['remainingTime']?.toString() ?? 'N/A';
    final remainingDistance = bus['remainingDistance']?.toString() ?? 'Calculating...';
    final matchedSchedule = vm.getMatchingSchedule(bus);

    String displayDistance = remainingDistance;
    String displayTime = remainingTime;

    if ((displayDistance == 'Calculating...' || displayDistance == '---' || displayDistance.isEmpty || displayDistance == 'N/A') ||
        (displayTime == 'Calculating...' || displayTime == '---' || displayTime.isEmpty || displayTime == 'N/A')) {
      final lat = (bus['latitude'] as num?)?.toDouble() ?? 0.0;
      final lng = (bus['longitude'] as num?)?.toDouble() ?? 0.0;
      if (lat != 0.0 && lng != 0.0) {
        final busFrom = (bus['from'] ?? '').toString();
        final busTo = (bus['to'] ?? '').toString();

        List<LatLng>? routePoints;
        final exactRouteKey = '$busFrom ➔ $busTo';
        if (vm.polylines.containsKey(exactRouteKey)) {
          routePoints = vm.polylines[exactRouteKey];
        } else {
          // Fuzzy match on keys
          for (final key in vm.polylines.keys) {
            final parts = key.split(RegExp(r'(➔|->|to)'));
            if (parts.length >= 2) {
              final kFrom = parts[0].trim().toLowerCase();
              final kTo = parts[1].trim().toLowerCase();
              final bFrom = busFrom.trim().toLowerCase();
              final bTo = busTo.trim().toLowerCase();

              bool matchPart(String actual, String filter) {
                final normActual = actual.replaceAll('campus', '').trim();
                final normFilter = filter.replaceAll('campus', '').trim();
                if (normActual == normFilter) return true;
                final abbasiaSpelling = ['abbasia', 'abasia', 'old'];
                if (abbasiaSpelling.any((s) => normActual.contains(s)) &&
                    abbasiaSpelling.any((s) => normFilter.contains(s))) {
                  return true;
                }
                return false;
              }

              if (matchPart(bFrom, kFrom) && matchPart(bTo, kTo)) {
                routePoints = vm.polylines[key];
                break;
              }
            }
          }
        }

        if (routePoints != null && routePoints.isNotEmpty) {
          final distanceUtil = const Distance();
          int minIndex = 0;
          double minDistance = double.infinity;

          for (int i = 0; i < routePoints.length; i++) {
            final dist = distanceUtil.as(LengthUnit.Meter, LatLng(lat, lng), routePoints[i]);
            if (dist < minDistance) {
              minDistance = dist;
              minIndex = i;
            }
          }

          double totalDistanceMeters = distanceUtil.as(LengthUnit.Meter, LatLng(lat, lng), routePoints[minIndex]);
          for (int i = minIndex; i < routePoints.length - 1; i++) {
            totalDistanceMeters += distanceUtil.as(LengthUnit.Meter, routePoints[i], routePoints[i + 1]);
          }

          final double currentSpeedKmh = speed > 5.0 ? speed : 25.0;
          final durationSeconds = (totalDistanceMeters / 1000) / currentSpeedKmh * 3600;

          if (displayDistance == 'Calculating...' || displayDistance == '---' || displayDistance.isEmpty || displayDistance == 'N/A') {
            if (totalDistanceMeters >= 1000) {
              displayDistance = "${(totalDistanceMeters / 1000).toStringAsFixed(1)} KM";
            } else {
              displayDistance = "${totalDistanceMeters.toInt()} M";
            }
          }
          if (displayTime == 'Calculating...' || displayTime == '---' || displayTime.isEmpty || displayTime == 'N/A') {
            final minutes = (durationSeconds / 60).ceil();
            if (minutes >= 60) {
              final hours = minutes ~/ 60;
              final mins = minutes % 60;
              displayTime = "${hours}h ${mins}m";
            } else {
              displayTime = "$minutes MIN";
            }
          }
        } else {
          LatLng? destinationCoord;
          final toLower = busTo.toLowerCase();
          if (toLower.contains('baghdad')) {
            destinationCoord = const LatLng(29.378047555871532, 71.75750718286565);
          } else if (toLower.contains('abbasia') || toLower.contains('abasia') || toLower.contains('old')) {
            destinationCoord = const LatLng(29.398239582972707, 71.69205655369649);
          } else if (toLower.contains('railway')) {
            destinationCoord = const LatLng(29.3970, 71.6850);
          }

          if (destinationCoord != null) {
            final distanceMeters = const Distance().as(LengthUnit.Meter, LatLng(lat, lng), destinationCoord);
            final adjustedDistance = distanceMeters * 1.3;
            final durationSeconds = (adjustedDistance / 1000) / 25.0 * 3600;

            if (displayDistance == 'Calculating...' || displayDistance == '---' || displayDistance.isEmpty || displayDistance == 'N/A') {
              if (adjustedDistance >= 1000) {
                displayDistance = "${(adjustedDistance / 1000).toStringAsFixed(1)} KM";
              } else {
                displayDistance = "${adjustedDistance.toInt()} M";
              }
            }
            if (displayTime == 'Calculating...' || displayTime == '---' || displayTime.isEmpty || displayTime == 'N/A') {
              final minutes = (durationSeconds / 60).ceil();
              if (minutes >= 60) {
                final hours = minutes ~/ 60;
                final mins = minutes % 60;
                displayTime = "${hours}h ${mins}m";
              } else {
                displayTime = "$minutes MIN";
              }
            }
          }
        }
      }
    }

    return Card(
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primaryNavy.withValues(
                    alpha: 0.08,
                  ),
                  radius: 20,
                  child: Icon(
                    Icons.directions_bus_outlined,
                    color: AppColors.primaryNavy,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bus #${bus['busNumber'] ?? 'N/A'}',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        'License Plate: $plate',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => vm.selectBus(null),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildCardMiniStat(
                    Icons.speed,
                    'Speed',
                    bus['status'] == 'force_stopped' ? '0 km/h' : '${speed.toStringAsFixed(0)} km/h',
                  ),
                  Container(width: 1, height: 28, color: AppColors.borderLight),
                  _buildCardMiniStat(
                    Icons.straighten_rounded,
                    'Distance',
                    bus['status'] == 'force_stopped' ? 'Stopped' : displayDistance,
                  ),
                  Container(width: 1, height: 28, color: AppColors.borderLight),
                  _buildCardMiniStat(
                    Icons.timer_outlined,
                    'ETA',
                    bus['status'] == 'force_stopped' ? 'Stopped' : displayTime,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: Colors.green,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Current Trip: ${bus['from'] ?? 'Start'} to ${bus['to'] ?? 'End'}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textDark,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (matchedSchedule != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_note_rounded,
                      size: 16,
                      color: AppColors.primaryNavy,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Active Schedule Covered',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            '${matchedSchedule.route} (${matchedSchedule.departureTime ?? 'N/A'})',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryNavy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Operational Status',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            'Ad-hoc Run (No Official Schedule Match)',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
             _buildDriverInfoSection(bus),
            if (bus['status'] == 'force_stopped') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.power_settings_new_rounded,
                      size: 16,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tracking Status',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                          Text(
                            'Live tracking terminated by Super Admin',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (context.read<LoginViewModel>().isSuperAdmin) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showForceStopConfirmation(context, bus, vm),
                icon: const Icon(Icons.power_settings_new_rounded, size: 16),
                label: Text(
                  'FORCE STOP TRACKING',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 0.8,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showForceStopConfirmation(
    BuildContext context,
    Map<String, dynamic> bus,
    FleetOperationsViewModel vm,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red.shade600,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Force Stop Tracking?',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to force stop tracking for Bus #${bus['busNumber'] ?? 'N/A'}?\n\nThis will remove the live bus from the tracking system and terminate the current trip run.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'CANCEL',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                
                // Show loading indicator
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Stopping tracking for Bus #${bus['busNumber']}...',
                          style: GoogleFonts.poppins(fontSize: 12),
                        ),
                      ],
                    ),
                    backgroundColor: AppColors.primaryNavy,
                    duration: const Duration(seconds: 2),
                  ),
                );

                await vm.forceStopTracking(bus);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Bus #${bus['busNumber']} has been stopped successfully.',
                        style: GoogleFonts.poppins(fontSize: 12),
                      ),
                      backgroundColor: Colors.green.shade600,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'FORCE STOP',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDriverInfoSection(Map<String, dynamic> bus) {
    final driverId = bus['driverId']?.toString() ?? '';
    if (driverId.isEmpty) {
      return _buildDriverInfoRow(
        name: bus['driverName'] ?? 'No Name',
        phone: 'N/A',
        email: 'N/A',
        experience: 'N/A',
        profileUrl: null,
        isVerified: false,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('drivers').doc(driverId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _buildDriverInfoRow(
            name: bus['driverName'] ?? 'No Name',
            phone: 'N/A',
            email: 'N/A',
            experience: 'N/A',
            profileUrl: null,
            isVerified: false,
          );
        }

        final driverData = snapshot.data!.data() ?? {};
        final name = driverData['name']?.toString() ?? bus['driverName'] ?? 'No Name';
        final phone = driverData['phoneNumber']?.toString() ?? 'N/A';
        final email = driverData['email']?.toString() ?? 'N/A';
        final experience = driverData['experience']?.toString() ?? 'N/A';
        final profileUrl = driverData['profileUrl']?.toString();
        final isVerified = driverData['isVerified'] as bool? ?? false;

        return _buildDriverInfoRow(
          name: name,
          phone: phone,
          email: email,
          experience: experience,
          profileUrl: profileUrl,
          isVerified: isVerified,
        );
      },
    );
  }

  Widget _buildDriverInfoRow({
    required String name,
    required String phone,
    required String email,
    required String experience,
    required String? profileUrl,
    required bool isVerified,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () {
          try {
            context.read<DashboardViewModel>().setSelectedIndex(2); // Drivers Screen
          } catch (e) {
            debugPrint("Navigation error: $e");
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.backgroundLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'ASSIGNED DRIVER DETAILS',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 11,
                        color: AppColors.primaryNavy.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                  if (isVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_rounded, color: Colors.blue, size: 10),
                          const SizedBox(width: 2),
                          Text(
                            'VERIFIED',
                            style: GoogleFonts.poppins(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primaryNavy.withValues(alpha: 0.1),
                    backgroundImage: profileUrl != null && profileUrl.isNotEmpty
                        ? NetworkImage(profileUrl)
                        : null,
                    child: profileUrl == null || profileUrl.isEmpty
                        ? Icon(Icons.person, color: AppColors.primaryNavy, size: 24)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.textDark,
                          ),
                        ),
                        Text(
                          'Experience: $experience',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, thickness: 0.5),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.phone_rounded, size: 14, color: AppColors.primaryNavy),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            phone,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.email_rounded, size: 14, color: AppColors.primaryNavy),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            email,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardMiniStat(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }

  List<Polyline> _buildMapPolylines(FleetOperationsViewModel vm) {
    final List<Polyline> list = [];

    // 1. If a specific route is filtered, show its polyline
    if (vm.selectedRouteFilter != 'All') {
      final points = vm.polylines[vm.selectedRouteFilter];
      if (points != null && points.isNotEmpty) {
        list.add(
          Polyline(
            points: points,
            strokeWidth: 4,
            color: AppColors.primaryNavy.withValues(alpha: 0.6),
          ),
        );
      }
    }

    // 2. If a bus is selected, show its polyline (if not already added as main filter)
    final selectedBus = vm.selectedBus;
    if (selectedBus != null) {
      final from = (selectedBus['from'] ?? '').toString().trim();
      final to = (selectedBus['to'] ?? '').toString().trim();
      final routeKey = '$from ➔ $to';

      if (routeKey != vm.selectedRouteFilter) {
        final points = vm.polylines[routeKey];
        if (points != null && points.isNotEmpty) {
          list.add(
            Polyline(
              points: points,
              strokeWidth: 4,
              color: AppColors.accentAmber.withValues(alpha: 0.4),
            ),
          );
        }
      }
    }

    return list;
  }

  List<Marker> _buildMapMarkers(FleetOperationsViewModel vm) {
    return vm.filteredBuses
        .where((bus) => bus['status'] != 'force_stopped')
        .map((bus) {
      final lat = (bus['latitude'] as num?)?.toDouble() ?? 0.0;
      final lng = (bus['longitude'] as num?)?.toDouble() ?? 0.0;
      final isSelected = vm.selectedBusId == bus['id'];
      final gender = (bus['gender'] ?? 'Combined').toString();
      final genderColor =
          gender.toLowerCase() == 'girls'
              ? Colors.pinkAccent
              : (gender.toLowerCase() == 'boys'
                  ? Colors.blueAccent
                  : Colors.teal);

      return Marker(
        point: LatLng(lat, lng),
        width: 100,
        height: 100,
        child: GestureDetector(
          onTap: () {
            vm.selectBus(bus['id']);
            _animatedMapMove(LatLng(lat, lng), 15.5);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Floating Bus Number Badge Tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primaryNavy : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppColors.accentAmber : genderColor,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '#${bus['busNumber'] ?? '??'}',
                  style: GoogleFonts.poppins(
                    color: isSelected ? Colors.white : AppColors.textDark,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Custom Pin Marker
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.accentAmber : genderColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.directions_bus_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  if (isSelected)
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.8, end: 1.4),
                      duration: const Duration(seconds: 1),
                      curve: Curves.easeInOut,
                      builder: (context, value, child) {
                        return Container(
                          width: 38 * value,
                          height: 38 * value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.accentAmber.withValues(
                                alpha: 1.0 - (value - 0.8) / 0.6,
                              ),
                              width: 1.5,
                            ),
                          ),
                        );
                      },
                      onEnd: () {},
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildScheduleProgressWidget(FleetOperationsViewModel vm) {
    final total = vm.totalSchedulesToday;
    final active = vm.activeSchedulesToday;
    final progress = total > 0 ? (active / total) : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryNavy.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryNavy.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.event_note_rounded,
                    color: AppColors.primaryNavy,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('yyyy-MM-dd').format(vm.selectedDate) ==
                            DateFormat('yyyy-MM-dd').format(DateTime.now())
                        ? "Today's Schedule Runs"
                        : "${DateFormat('MMM d').format(vm.selectedDate)} Schedule Runs",
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              Text(
                "$active / $total Active",
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentAmber),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarSection(FleetOperationsViewModel vm) {
    final days = vm.daysInMonth;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.01),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    color: AppColors.primaryNavy,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${vm.monthName} ${vm.currentMonth.year}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      vm.changeMonth(-1);
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _scrollToSelectedDate(),
                      );
                    },
                    icon: const Icon(Icons.chevron_left_rounded, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.backgroundLight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () {
                      vm.changeMonth(1);
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _scrollToSelectedDate(),
                      );
                    },
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.backgroundLight,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: ListView.builder(
              controller: _calendarScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              itemBuilder: (context, index) {
                final dayDate = days[index];
                final isSelected =
                    dayDate.day == vm.selectedDate.day &&
                    dayDate.month == vm.selectedDate.month &&
                    dayDate.year == vm.selectedDate.year;

                return GestureDetector(
                  onTap: () {
                    vm.selectDate(dayDate);
                  },
                  child: Container(
                    width: 50,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color:
                          isSelected
                              ? AppColors.primaryNavy
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            isSelected
                                ? Colors.transparent
                                : AppColors.borderLight,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          vm
                              .getWeekdayName(dayDate)
                              .substring(0, 3)
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color:
                                isSelected
                                    ? Colors.white70
                                    : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dayDate.day.toString(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color:
                                isSelected ? Colors.white : AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BusListItem extends StatefulWidget {
  final Map<String, dynamic> bus;
  final bool isSelected;
  final double speed;
  final DateTime lastUpdated;
  final BusSchedule? matchedSchedule;
  final VoidCallback onTap;

  const _BusListItem({
    required this.bus,
    required this.isSelected,
    required this.speed,
    required this.lastUpdated,
    this.matchedSchedule,
    required this.onTap,
  });

  @override
  State<_BusListItem> createState() => _BusListItemState();
}

class _BusListItemState extends State<_BusListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final gender = (widget.bus['gender'] ?? 'Combined').toString();
    final genderColor =
        gender.toLowerCase() == 'girls'
            ? Colors.pinkAccent
            : (gender.toLowerCase() == 'boys'
                ? Colors.blueAccent
                : Colors.teal);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.bus['status'] == 'force_stopped'
                ? (widget.isSelected || _isHovered
                    ? Colors.red.withValues(alpha: 0.08)
                    : Colors.red.withValues(alpha: 0.03))
                : (widget.isSelected || _isHovered
                    ? AppColors.primaryNavy.withValues(alpha: 0.04)
                    : Colors.white),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.bus['status'] == 'force_stopped'
                  ? (widget.isSelected
                      ? Colors.red
                      : (_isHovered
                          ? Colors.red.withValues(alpha: 0.5)
                          : Colors.red.withValues(alpha: 0.2)))
                  : (widget.isSelected
                      ? AppColors.primaryNavy
                      : (_isHovered
                          ? AppColors.primaryNavy.withValues(alpha: 0.3)
                          : AppColors.borderLight)),
              width: widget.isSelected ? 1.5 : 1.0,
            ),
            boxShadow:
                _isHovered
                    ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                    : null,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // Bus Icon badge
                  AnimatedScale(
                    scale: _isHovered ? 1.1 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.bus['status'] == 'force_stopped'
                            ? Colors.red.withValues(alpha: 0.08)
                            : AppColors.primaryNavy.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.directions_bus_filled,
                        color: widget.bus['status'] == 'force_stopped'
                            ? Colors.red
                            : AppColors.primaryNavy,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Bus #${widget.bus['busNumber'] ?? 'N/A'}',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Gender Tag
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: genderColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                gender.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: genderColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Driver: ${widget.bus['driverName'] ?? 'No Name'}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Pulse Animation Indicator
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.bus['status'] == 'force_stopped'
                          ? Colors.red
                          : Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: AppColors.borderLight),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.route_outlined,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${widget.bus['from'] ?? 'Start'} ➔ ${widget.bus['to'] ?? 'End'}',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  widget.bus['status'] == 'force_stopped'
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'STOPPED',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                        )
                      : Text(
                          '${widget.speed.toStringAsFixed(0)} km/h',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.matchedSchedule != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryNavy.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_note_rounded,
                        size: 12,
                        color: AppColors.primaryNavy,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Schedule: ${widget.matchedSchedule!.departureTime ?? 'Live'} Run',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: AppColors.primaryNavy,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 12,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Ad-hoc/Unscheduled Run',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: Colors.orange[800],
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
