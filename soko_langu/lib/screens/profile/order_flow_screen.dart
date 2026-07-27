import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import '../../main.dart' show AppConfig;

class OrderFlowScreen extends StatefulWidget {
  const OrderFlowScreen({super.key});

  @override
  State<OrderFlowScreen> createState() => _OrderFlowScreenState();
}

class _OrderFlowScreenState extends State<OrderFlowScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          context.tr('how_it_works'),
          style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final isEn = AppConfig.of(context).langCode == 'en';
          final details = isEn ? flowDetails : flowDetailsSW;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              ...List.generate(flowNodes.length, (index) {
                final node = flowNodes[index];
                final isLast = index == flowNodes.length - 1;
                return _FlowNodeCard(
                  node: node,
                  index: index,
                  isLast: isLast,
                  cs: cs,
                  pulse: _pulse.value,
                  detail: details[index],
                );
              }),
              const SizedBox(height: 24),
              _FeeBreakdownCard(cs: cs, isEn: isEn),
            ],
          );
        },
      ),
    );
  }
}

class _FlowNodeCard extends StatelessWidget {
  final _FlowNode node;
  final int index;
  final bool isLast;
  final ColorScheme cs;
  final double pulse;
  final (String, String) detail;

  const _FlowNodeCard({
    required this.node,
    required this.index,
    required this.isLast,
    required this.cs,
    required this.pulse,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final stepNum = index + 1;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 64,
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  transform: Matrix4.identity()..scale(pulse),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [node.color.withValues(alpha: 0.85), node.color],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: node.color.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(node.icon, color: Colors.white, size: 24),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cs.surface,
                            border: Border.all(color: node.color, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              '$stepNum',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: node.color,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            node.color.withValues(alpha: 0.7),
                            flowNodes[index + 1].color.withValues(alpha: 0.25),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: cs.surface.withValues(alpha: 0.55),
                border: Border.all(
                  color: node.color.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: node.color.withValues(alpha: 0.15),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(node.icon, size: 12, color: node.color),
                                const SizedBox(width: 5),
                                Text(
                                  flowLabels[index],
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: node.color,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          _PhaseBadge(
                            label: phaseLabels[index],
                            color: node.color,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.tr(node.titleKey),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildDataRow(detail.$1, detail.$2, node.color, cs),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(String left, String right, Color color, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.06),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 6, color: color.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              left,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
          Text(
            right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _PhaseBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _FeeEntry {
  final String label;
  final String value;
  final bool isHeader;
  const _FeeEntry(this.label, this.value, {this.isHeader = false});
}

class _FeeBreakdownCard extends StatelessWidget {
  final ColorScheme cs;
  final bool isEn;
  const _FeeBreakdownCard({required this.cs, required this.isEn});

  @override
  Widget build(BuildContext context) {
    final fees = isEn ? feeBreakdownEN : feeBreakdownSW;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: cs.surface.withValues(alpha: 0.55),
        border: Border.all(color: cs.primary.withValues(alpha: 0.15), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                isEn ? 'Fee Breakdown' : 'Mgawanyo wa Ada',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...fees.map((f) {
            if (f.isHeader) {
              return Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 16,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      f.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.circle, size: 6, color: cs.primary.withValues(alpha: 0.6)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    f.value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: cs.primary.withValues(alpha: 0.08),
            ),
            child: Text(
              isEn
                ? '💡 Choose any payment method at checkout. Wallet is free (deposit via USSD or Lipa Namba first). USSD Push sends a phone prompt. Lipa Namba, Card, and BillPay are instant.'
                : '💡 Chagua njia yoyote ya malipo wakati wa checkout. Pochi ni bure (weka hela kwanza kwa USSD au Lipa Namba). USSD Push inatuma kidokezo kwenye simu. Lipa Namba, Kadi, na BillPay ni papo hapo.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurface.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowNode {
  final IconData icon;
  final String titleKey;
  final Color color;
  const _FlowNode({
    required this.icon,
    required this.titleKey,
    required this.color,
  });
}

final flowNodes = [
  _FlowNode(
    icon: Icons.shopping_cart_outlined,
    titleKey: 'flow_place_order',
    color: const Color(0xFF4A90D9),
  ),
  _FlowNode(
    icon: Icons.receipt_long_outlined,
    titleKey: 'flow_shipping_quote',
    color: const Color(0xFF14B8A6),
  ),
  _FlowNode(
    icon: Icons.phone_android_outlined,
    titleKey: 'flow_payment',
    color: const Color(0xFF059669),
  ),
  _FlowNode(
    icon: Icons.verified_user_outlined,
    titleKey: 'flow_escrow',
    color: const Color(0xFFD97706),
  ),
  _FlowNode(
    icon: Icons.inventory_2_outlined,
    titleKey: 'flow_dispatch',
    color: const Color(0xFFEA580C),
  ),
  _FlowNode(
    icon: Icons.check_circle_outlined,
    titleKey: 'flow_confirm',
    color: const Color(0xFF7C3AED),
  ),
  _FlowNode(
    icon: Icons.emoji_events_outlined,
    titleKey: 'flow_complete',
    color: const Color(0xFFEC4899),
  ),
];

final flowLabels = [
  'ORDER',
  'QUOTE',
  'PAYMENT',
  'ESCROW',
  'DISPATCH',
  'CONFIRM',
  'COMPLETE',
];

final phaseLabels = [
  'INITIATION',
  'PRICING',
  'TRANSACTION',
  'HOLD',
  'LOGISTICS',
  'VERIFICATION',
  'SETTLEMENT',
];

final flowDetails = [
  ('Order is placed • Seller will confirm', ''),
  ('Seller sets shipping cost', ''),
  ('Buyer pays via Wallet, USSD, Lipa Namba, Card, or BillPay', ''),
  ('Funds held securely in escrow', ''),
  ('Seller dispatches via courier', ''),
  ('Buyer confirms receipt', ''),
  ('Seller receives payout to mobile money', ''),
];

final flowDetailsSW = [
  ('Oda imewekwa • Muuzaji atathibitisha', ''),
  ('Muuzaji anaweka gharama ya usafiri', ''),
  ('Mnunuzi analipa kwa Pochi, USSD, Lipa Namba, Kadi, au BillPay', ''),
  ('Fedha zinalindwa kwenye escrow', ''),
  ('Muuzaji anasafirisha bidhaa', ''),
  ('Mnunuzi anathibitisha upokeaji', ''),
  ('Muuzaji anapokea malipo kwenye simu yake', ''),
];

final feeBreakdownEN = [
  _FeeEntry('By Payment Method', '', isHeader: true),
  _FeeEntry('Wallet (deposit first)', 'Free'),
  _FeeEntry('USSD Push (M-Pesa, Tigo, Airtel)', 'TZS 54 – 7,960'),
  _FeeEntry('TanQR / Lipa Namba', '2%'),
  _FeeEntry('Card (Mastercard/Visa/UnionPay)', '4.85%'),
  _FeeEntry('BillPay (M-Pesa, Airtel, Tigo)', '1%'),
  _FeeEntry('Other Fees', '', isHeader: true),
  _FeeEntry('Soko Vibe Commission', '3.5% of product price'),
  _FeeEntry('Shipping Cost', 'Set by seller, paid by buyer'),
  _FeeEntry('Seller Withdrawal to Mobile', 'TZS 52 – 9,890'),
  _FeeEntry('Example: TZS 50,000 via USSD', '', isHeader: true),
  _FeeEntry('Gateway Fee (USSD tier)', 'TZS 2,136'),
  _FeeEntry('Soko Vibe Commission (3.5%)', 'TZS 1,750'),
  _FeeEntry('Total Buyer Pays', 'TZS 53,886'),
  _FeeEntry('Seller Receives (before payout)', 'TZS 48,250'),
];

final feeBreakdownSW = [
  _FeeEntry('Kwa Njia ya Malipo', '', isHeader: true),
  _FeeEntry('Pochi (weka hela kwanza)', 'Bure'),
  _FeeEntry('USSD Push (M-Pesa, Tigo, Airtel)', 'TZS 54 – 7,960'),
  _FeeEntry('TanQR / Lipa Namba', '2%'),
  _FeeEntry('Kadi (Mastercard/Visa/UnionPay)', '4.85%'),
  _FeeEntry('BillPay (M-Pesa, Airtel, Tigo)', '1%'),
  _FeeEntry('Ada Nyingine', '', isHeader: true),
  _FeeEntry('Ada ya Soko Vibe', '3.5% ya bei'),
  _FeeEntry('Gharama ya Usafirishaji', 'Inawekwa na muuzaji'),
  _FeeEntry('Muuzaji Kutoa Pesa', 'TZS 52 – 9,890'),
  _FeeEntry('Mfano: TZS 50,000 kwa USSD', '', isHeader: true),
  _FeeEntry('Ada ya USSD', 'TZS 2,136'),
  _FeeEntry('Ada ya Soko Vibe (3.5%)', 'TZS 1,750'),
  _FeeEntry('Jumla Mnunuzi Analipa', 'TZS 53,886'),
  _FeeEntry('Muuzaji Anapata (kabla ya kutoa)', 'TZS 48,250'),
];
