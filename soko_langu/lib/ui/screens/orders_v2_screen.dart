import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/order_model.dart';
import '../../services/order_api.dart';
import '../tokens.dart';
import '../widgets/ui_button.dart';

class OrdersV2Screen extends StatefulWidget {
  const OrdersV2Screen({super.key});

  @override
  State<OrdersV2Screen> createState() => _OrdersV2ScreenState();
}

class _OrdersV2ScreenState extends State<OrdersV2Screen> {
  late Future<({List<OrderData> orders, int total})> _future;
  final _api = OrderApiClient();

  @override
  void initState() {
    super.initState();
    _future = _api.fetchOrders(limit: 30);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Maagizo yangu')),
      body: FutureBuilder<({List<OrderData> orders, int total})>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Message(
              text: 'Imeshindikana kupakia maagizo.',
              action: 'Jaribu tena',
              onPressed: () => setState(() => _future = _api.fetchOrders(limit: 30)),
            );
          }
          final orders = snap.data?.orders ?? const [];
          if (orders.isEmpty) {
            return const _Message(text: 'Huna maagizo bado.');
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _api.fetchOrders(limit: 30)),
            child: ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _OrderRow(order: orders[i]),
            ),
          );
        },
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final OrderData order;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(UiSpace.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.productName, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: UiSpace.xs),
                Text('TSh ${order.totalAmount}', style: Theme.of(context).textTheme.bodyMedium),
                Text(order.status, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(order.orderNumber, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action, this.onPressed});

  final String text;
  final String? action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(UiSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: UiSpace.md),
              UiPrimaryButton(label: action!, onPressed: onPressed),
            ],
          ],
        ),
      ),
    );
  }
}
