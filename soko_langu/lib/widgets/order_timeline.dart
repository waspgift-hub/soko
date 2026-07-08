import 'package:flutter/material.dart';
import '../theme/app_dimens.dart';
import '../models/transaction_model.dart';

class OrderTimeline extends StatelessWidget {
  final TransactionStatus status;
  final Map<String, dynamic>? dispatchProof;
  final String? courierName;
  final String? driverPhone;
  final String? receiptImageUrl;
  final String? trackingNumber;
  final double? shippingCost;
  final Map<String, dynamic>? deliveryAddress;
  final String? orderId;
  final String? passengerName;
  final String? busName;
  final String? receiptNumber;
  final String? departureTime;
  final String? arrivalTime;
  final String? originStation;
  final String? destinationStation;
  final String? travelDate;
  final String? travelDay;
  final double? shippingFare;
  final String? plateNumber;
  final dynamic productReceipt;

  const OrderTimeline({
    super.key,
    required this.status,
    this.dispatchProof,
    this.courierName,
    this.driverPhone,
    this.receiptImageUrl,
    this.trackingNumber,
    this.shippingCost,
    this.deliveryAddress,
    this.orderId,
    this.passengerName,
    this.busName,
    this.receiptNumber,
    this.departureTime,
    this.arrivalTime,
    this.originStation,
    this.destinationStation,
    this.travelDate,
    this.travelDay,
    this.shippingFare,
    this.plateNumber,
    this.productReceipt,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final steps = _buildSteps();
    final currentStep = _currentStepIndex();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(steps.length, (i) {
          final isActive = i <= currentStep;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? cs.primary : cs.surfaceContainerHighest,
                  ),
                  child: Icon(Icons.check, size: 14, color: isActive ? cs.onPrimary : Colors.transparent),
                ),
                const SizedBox(width: AppInsets.sm),
                Flexible(child: Text(steps[i], style: TextStyle(fontSize: 13, color: isActive ? cs.onSurface : cs.onSurfaceVariant))),
              ],
            ),
          );
        }),
        if (busName != null || plateNumber != null || trackingNumber != null) ...[
          const SizedBox(height: 8),
          if (busName != null) _infoRow('Bus', busName!, cs),
          if (plateNumber != null) _infoRow('Plate', plateNumber!, cs),
          if (trackingNumber != null) _infoRow('Tracking', trackingNumber!, cs),
        ],
      ],
    );
  }

  int _currentStepIndex() {
    switch (status) {
      case TransactionStatus.pending: return 0;
      case TransactionStatus.awaitingShippingQuote: return 1;
      case TransactionStatus.awaitingPayment: return 2;
      case TransactionStatus.paidEscrowHeld:
      case TransactionStatus.escrowHold: return 3;
      case TransactionStatus.dispatched: return 4;
      case TransactionStatus.delivered: return 5;
      case TransactionStatus.completed: return 6;
      default: return 0;
    }
  }

  List<String> _buildSteps() {
    return ['Ordered', 'Quote', 'Payment', 'Escrow', 'Dispatched', 'Confirmed', 'Delivered'];
  }

  Widget _infoRow(String label, String value, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          Text(value, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
