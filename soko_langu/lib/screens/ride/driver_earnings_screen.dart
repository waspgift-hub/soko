import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/ride_provider.dart';
import '../../models/ride_models.dart';
import '../../extensions/context_tr.dart';

class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RideProvider>().fetchEarnings();
      context.read<RideProvider>().fetchDriverRides();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<RideProvider>();
    final earnings = provider.earnings;
    final rides = provider.driverRides;
    final nf = NumberFormat('#,##0', 'en');

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(context.tr('driver_earnings')),
        backgroundColor: cs.surface,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await provider.fetchEarnings();
          await provider.fetchDriverRides();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (earnings != null) ...[
              _buildEarningsCard(context, cs, earnings, nf),
              const SizedBox(height: 16),
            ],
            if (provider.loading)
              const Center(child: CircularProgressIndicator())
            else if (rides.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text(context.tr('no_rides_yet'),
                    style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              )
            else
              ...rides.map((ride) => _buildRideCard(context, cs, ride, nf)),
          ],
        ),
      ),
    );
  }

  Widget _buildEarningsCard(BuildContext context, ColorScheme cs, DriverEarnings e, NumberFormat nf) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(context.tr('total_earnings'),
            style: TextStyle(fontSize: 14, color: cs.onPrimary.withValues(alpha: 0.8))),
          const SizedBox(height: 4),
          Text('TSh ${nf.format(e.totalEarnings)}',
            style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: cs.onPrimary)),
          const SizedBox(height: 16),
          Row(
            children: [
              _statItem(cs, context.tr('today'), 'TSh ${nf.format(e.todayEarnings)}'),
              const SizedBox(width: 16),
              _statItem(cs, context.tr('this_week'), 'TSh ${nf.format(e.weekEarnings)}'),
              const SizedBox(width: 16),
              _statItem(cs, context.tr('rides'), '${e.completedRides}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(ColorScheme cs, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onPrimary)),
          Text(label, style: TextStyle(fontSize: 11, color: cs.onPrimary.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _buildRideCard(BuildContext context, ColorScheme cs, Ride ride, NumberFormat nf) {
    final completed = ride.status == 'PAYMENT_COMPLETED' || ride.status == 'COMPLETED';
    final cancelled = ride.status == 'CANCELLED';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: completed
                ? Colors.green.withValues(alpha: 0.1)
                : cancelled
                    ? cs.error.withValues(alpha: 0.1)
                    : cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            completed ? Icons.paid : cancelled ? Icons.cancel : Icons.schedule,
            color: completed ? Colors.green : cancelled ? cs.error : cs.primary,
            size: 20,
          ),
        ),
        title: Text('${ride.pickup.address} → ${ride.dropoff.address}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w500, color: cs.onSurface)),
        subtitle: Text('${ride.distanceKm} km · ${ride.durationMin} min',
          style: TextStyle(color: cs.onSurfaceVariant)),
        trailing: Text('TSh ${nf.format(ride.finalFare ?? ride.fare)}',
          style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
      ),
    );
  }
}
