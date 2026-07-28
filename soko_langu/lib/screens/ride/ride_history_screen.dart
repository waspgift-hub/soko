import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/ride_provider.dart';
import '../../models/ride_models.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<RideProvider>();
      provider.fetchRiderRides();
      if (provider.isDriver) provider.fetchDriverRides();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<RideProvider>();
    final isDriver = provider.isDriver;
    final rides = isDriver ? provider.driverRides : provider.riderRides;
    final nf = NumberFormat('#,##0', 'en');

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(context.tr('ride_history')),
        backgroundColor: cs.surface,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (isDriver) {
            await provider.fetchDriverRides();
          } else {
            await provider.fetchRiderRides();
          }
        },
        child: rides.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 16),
                    Text(context.tr('no_rides_yet'),
                      style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rides.length,
                itemBuilder: (ctx, i) => _buildRideCard(context, cs, rides[i], nf),
              ),
      ),
    );
  }

  Widget _buildRideCard(BuildContext context, ColorScheme cs, Ride ride, NumberFormat nf) {
    final isActive = ride.isActive;
    final isCancelled = ride.status == 'CANCELLED';
    final isPaid = ride.status == 'PAID';

    Color statusColor;
    String statusLabel;
    if (isActive) {
      statusColor = Colors.orange;
      statusLabel = context.tr('in_progress');
    } else if (isCancelled) {
      statusColor = cs.error;
      statusLabel = context.tr('cancelled');
    } else if (isPaid) {
      statusColor = Colors.green;
      statusLabel = context.tr('completed');
    } else {
      statusColor = cs.onSurfaceVariant;
      statusLabel = ride.status;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isActive
            ? () => context.push('${AppRoutes.rideTracking}/${ride.rideId}')
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.directions_car,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${ride.pickup.address} → ${ride.dropoff.address}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w500, color: cs.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${ride.distanceKm} km',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                'TSh ${nf.format(ride.finalFare ?? ride.fare)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
