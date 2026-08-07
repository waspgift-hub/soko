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
    _pulse = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
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
              // ── Order Flow Timeline ──
              _SectionHeader(
                icon: Icons.route_outlined,
                title: isEn ? 'Order Flow' : 'Mlolongo wa Oda',
                cs: cs,
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 32),

              // ── Fee Sections (kept from original) ──
              _SectionHeader(
                icon: Icons.payments_outlined,
                title: isEn ? 'ClickPesa Collection Fees' : 'Ada za Kukusanya za ClickPesa',
                cs: cs,
              ),
              const SizedBox(height: 8),
              _InfoCard(
                cs: cs,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SubHeader(cs: cs, text: isEn ? 'USSD Push (M-Pesa, Airtel, Tigo, HaloPesa)' : 'USSD Push (M-Pesa, Airtel, Tigo, HaloPesa)'),
                    const SizedBox(height: 4),
                    Text(
                      isEn ? 'Charged to the customer on top of MNO fees.' : 'Inatozwa kwa mteja juu ya ada za MNO.',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 12),
                    _FeeTiersTable(cs: cs, tiers: ussdPushTiers),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(
                icon: Icons.payments_outlined,
                title: isEn ? 'ClickPesa Payout Fees' : 'Ada za Kutoa za ClickPesa',
                cs: cs,
              ),
              const SizedBox(height: 8),
              _InfoCard(
                cs: cs,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SubHeader(cs: cs, text: isEn ? 'Mobile Money Payouts (M-Pesa, Airtel, Tigo)' : 'Malipo ya Pesa kwa Simu (M-Pesa, Airtel, Tigo)'),
                    const SizedBox(height: 4),
                    Text(
                      isEn ? 'Charged to the business. Can be passed to the recipient.' : 'Inatozwa kwa biashara. Inaweza kupitishwa kwa mpokeaji.',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 12),
                    _FeeTiersTable(cs: cs, tiers: payoutTiers),
                    const SizedBox(height: 10),
                    _SubHeader(cs: cs, text: isEn ? 'Bank EFT / ACH' : 'Benki EFT / ACH'),
                    _PctRow(cs: cs, label: isEn ? 'Flat fee (0 \u2013 20,000,000 TZS)' : 'Ada isiyobadilika (0 \u2013 20,000,000 TZS)', value: 'TZS 2,360'),
                    const SizedBox(height: 10),
                    _SubHeader(cs: cs, text: isEn ? 'Bank TISS (TZS)' : 'Benki TISS (TZS)'),
                    _PctRow(cs: cs, label: isEn ? 'Flat fee (0 \u2013 1,000,000,000 TZS)' : 'Ada isiyobadilika (0 \u2013 1,000,000,000 TZS)', value: 'TZS 11,800'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(
                icon: Icons.store_outlined,
                title: isEn ? 'Soko Vibe Fees' : 'Ada za Soko Vibe',
                cs: cs,
              ),
              const SizedBox(height: 8),
              _InfoCard(
                cs: cs,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SubHeader(cs: cs, text: isEn ? 'Platform Commission' : 'Ada ya Tovuti'),
                    _PctRow(cs: cs, label: isEn ? 'Charged per completed sale' : 'Inatozwa kwa kila mauzo yaliyokamilika', value: '3.5%'),
                    const SizedBox(height: 6),
                    Text(
                      isEn
                        ? 'The 3.5% commission is deducted from the seller\'s payout and recorded as Soko Vibe revenue.'
                        : 'Ada ya 3.5% inakatwa kutoka kwa malipo ya muuzaji na kurekodiwa kama mapato ya Soko Vibe.',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 10),
                    _SubHeader(cs: cs, text: isEn ? 'Account & Channel Setup' : 'Ufunguzi wa Akaunti na Njia'),
                    const SizedBox(height: 4),
                    _FeeRow(cs: cs, label: isEn ? 'Account Creation (100,000 TZS limit)' : 'Ufunguzi wa Akaunti (kiwango 100,000 TZS)', value: 'Free'),
                    _FeeRow(cs: cs, label: isEn ? 'KYC Search and Onboarding' : 'Utafutaji wa KYC', value: 'TZS 25,000'),
                    _FeeRow(cs: cs, label: isEn ? 'M-Pesa Channel Setup' : 'Ufunguzi wa Njia ya M-Pesa', value: 'TZS 250,000'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(
                icon: Icons.receipt_long_outlined,
                title: isEn ? 'Fee Breakdown by Method' : 'Mgawanyo wa Ada kwa Njia',
                cs: cs,
              ),
              const SizedBox(height: 8),
              _InfoCard(
                cs: cs,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SubHeader(cs: cs, text: isEn ? 'USSD Push' : 'USSD Push'),
                    _PctRow(cs: cs, label: isEn ? 'Gateway fee (tiered)' : 'Ada ya malipo (kwa viwango)', value: 'TZS 54 \u2013 7,960'),
                    _PctRow(cs: cs, label: isEn ? 'Soko Vibe commission' : 'Ada ya Soko Vibe', value: '3.5%'),
                    const SizedBox(height: 16),
                    _SubHeader(cs: cs, text: isEn ? 'Seller Withdrawal (payout)' : 'Muuzaji Kutoa Pesa'),
                    _PctRow(cs: cs, label: isEn ? 'Payout fee (tiered)' : 'Ada ya kutoa (kwa viwango)', value: 'TZS 52 \u2013 9,890'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(
                icon: Icons.calculate_outlined,
                title: isEn ? 'Example: TZS 100,000 via USSD Push' : 'Mfano: TZS 100,000 kwa USSD Push',
                cs: cs,
              ),
              const SizedBox(height: 8),
              _InfoCard(
                cs: cs,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SubHeader(cs: cs, text: isEn ? 'USSD Push' : 'USSD Push'),
                    _CalcRow(cs: cs, label: isEn ? 'Product Price' : 'Bei ya Bidhaa', value: 'TZS 100,000'),
                    _CalcRow(cs: cs, label: isEn ? 'ClickPesa Gateway Fee (tiered)' : 'Ada ya ClickPesa (kwa viwango)', value: 'TZS 3,240'),
                    _CalcRow(cs: cs, label: isEn ? 'Soko Vibe Commission (3.5%)' : 'Ada ya Soko Vibe (3.5%)', value: 'TZS 3,500'),
                    const Divider(height: 20),
                    _CalcRow(cs: cs, label: isEn ? 'Total Buyer Pays' : 'Jumla Mnunuzi Analipa', value: 'TZS 106,740', bold: true, color: cs.primary),
                    const SizedBox(height: 8),
                    _CalcRow(cs: cs, label: isEn ? 'Seller Receives (before payout fee)' : 'Muuzaji Anapata (kabla ya ada ya kutoa)', value: 'TZS 96,500', bold: true, color: cs.tertiary),
                    const SizedBox(height: 4),
                    _CalcRow(cs: cs, label: isEn ? 'Payout Fee (estimated)' : 'Ada ya Kutoa (makadirio)', value: 'TZS 1,868 \u2013 9,890'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: cs.primary.withValues(alpha: 0.08),
                ),
                child: Text(
                  isEn
                    ? 'At checkout, USSD Push is the only payment method. You will receive a payment prompt on your phone \u2014 enter your PIN to complete the payment.'
                    : 'Wakati wa checkout, USSD Push ndiyo njia pekee ya malipo. Utapokea kidokezo cha malipo kwenye simu yako \u2014 weka PIN kukamilisha malipo.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Sub-widgets ───

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final ColorScheme cs;
  const _SectionHeader({required this.icon, required this.title, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}

class _SubHeader extends StatelessWidget {
  final ColorScheme cs;
  final String text;
  const _SubHeader({required this.cs, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.85)),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final ColorScheme cs;
  final Widget child;
  const _InfoCard({required this.cs, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: cs.surface.withValues(alpha: 0.55),
        border: Border.all(color: cs.primary.withValues(alpha: 0.1), width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: child,
        ),
      ),
    );
  }
}

class _PctRow extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final String value;
  const _PctRow({required this.cs, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 4),
      child: Row(
        children: [
          Icon(Icons.circle, size: 5, color: cs.primary.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.75))),
          ),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
        ],
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final String value;
  const _FeeRow({required this.cs, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, left: 4),
      child: Row(
        children: [
          Icon(Icons.circle, size: 4, color: cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6))),
          ),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

class _CalcRow extends StatelessWidget {
  final ColorScheme cs;
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  const _CalcRow({required this.cs, required this.label, required this.value, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final clr = color ?? cs.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 14 : 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: clr.withValues(alpha: bold ? 1.0 : 0.75),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: FontWeight.w800,
              color: clr,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeeTiersTable extends StatelessWidget {
  final ColorScheme cs;
  final List<(int, int, int)> tiers;
  const _FeeTiersTable({required this.cs, required this.tiers});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              Expanded(child: Text(context.tr('min_tzs_header'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary))),
              Expanded(child: Text(context.tr('max_tzs_header'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary))),
              Expanded(child: Text(context.tr('fee_tzs_header'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary), textAlign: TextAlign.end)),
            ],
          ),
        ),
        ...List.generate(tiers.length, (i) {
          final isEven = i % 2 == 0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: isEven ? Colors.transparent : cs.primary.withValues(alpha: 0.03),
              border: i == tiers.length - 1
                ? null
                : Border(bottom: BorderSide(color: cs.primary.withValues(alpha: 0.06), width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(child: Text(_fmt(tiers[i].$1), style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7)))),
                Expanded(child: Text(_fmt(tiers[i].$2), style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7)))),
                Expanded(child: Text(_fmt(tiers[i].$3), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.primary), textAlign: TextAlign.end)),
              ],
            ),
          );
        }),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.06),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
          ),
          child: Row(
            children: [
              const Spacer(),
              Text(context.tr('above_fee_info'),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.primary.withValues(alpha: 0.8))),
            ],
          ),
        ),
      ],
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)},${(n % 1000).toString().padLeft(3, '0')}';
    return n.toString();
  }
}

// ─── Data ───

class _FlowNode {
  final IconData icon;
  final String titleKey;
  final Color color;
  const _FlowNode({required this.icon, required this.titleKey, required this.color});
}

final flowNodes = [
  _FlowNode(icon: Icons.shopping_cart_outlined, titleKey: 'flow_place_order', color: const Color(0xFF4A90D9)),
  _FlowNode(icon: Icons.receipt_long_outlined, titleKey: 'flow_shipping_quote', color: const Color(0xFF14B8A6)),
  _FlowNode(icon: Icons.phone_android_outlined, titleKey: 'flow_payment', color: const Color(0xFF059669)),
  _FlowNode(icon: Icons.verified_user_outlined, titleKey: 'flow_escrow', color: const Color(0xFFD97706)),
  _FlowNode(icon: Icons.inventory_2_outlined, titleKey: 'flow_dispatch', color: const Color(0xFFEA580C)),
  _FlowNode(icon: Icons.check_circle_outlined, titleKey: 'flow_confirm', color: const Color(0xFF7C3AED)),
  _FlowNode(icon: Icons.emoji_events_outlined, titleKey: 'flow_complete', color: const Color(0xFFEC4899)),
];

final flowDetails = [
  ('Order is placed', 'Seller will confirm'),
  ('Seller sets shipping cost', ''),
  ('Buyer pays via USSD Push', ''),
  ('Funds held securely in escrow', ''),
  ('Seller dispatches via courier', ''),
  ('Buyer confirms receipt', ''),
  ('Seller receives payout to mobile money', ''),
];

final flowDetailsSW = [
  ('Oda imewekwa', 'Muuzaji atathibitisha'),
  ('Muuzaji anaweka gharama ya usafiri', ''),
  ('Mnunuzi analipa kwa USSD Push', ''),
  ('Fedha zinalindwa kwenye escrow', ''),
  ('Muuzaji anasafirisha bidhaa', ''),
  ('Mnunuzi anathibitisha upokeaji', ''),
  ('Muuzaji anapokea malipo kwenye simu yake', ''),
];

final flowLabels = ['ORDER', 'QUOTE', 'PAYMENT', 'ESCROW', 'DISPATCH', 'CONFIRM', 'COMPLETE'];
final phaseLabels = ['INITIATION', 'PRICING', 'TRANSACTION', 'HOLD', 'LOGISTICS', 'VERIFICATION', 'SETTLEMENT'];

final ussdPushTiers = <(int, int, int)>[
  (500, 899, 54), (900, 1999, 92), (2000, 2999, 124), (3000, 3999, 230),
  (4000, 4399, 380), (4400, 8999, 580), (9000, 19999, 920), (20000, 39999, 1150),
  (40000, 49999, 1572), (50000, 95999, 2136), (96000, 199999, 3240),
  (200000, 299999, 3660), (300000, 399999, 4080), (400000, 499999, 4340),
  (500000, 599999, 4820), (600000, 799999, 5230), (800000, 999999, 6146),
  (1000000, 1999999, 7210), (2000000, 3000000, 7960),
];

final payoutTiers = <(int, int, int)>[
  (100, 999, 52), (1000, 1999, 72), (2000, 2999, 104), (3000, 3999, 116),
  (4000, 4999, 168), (5000, 6999, 234), (7000, 7999, 360), (8000, 9999, 430),
  (10000, 14999, 642), (15000, 19999, 680), (20000, 29999, 700), (30000, 39999, 980),
  (40000, 49999, 1038), (50000, 99999, 1460), (100000, 199999, 1868),
  (200000, 299999, 2220), (300000, 399999, 3180), (400000, 499999, 3764),
  (500000, 599999, 4672), (600000, 699999, 5712), (700000, 799999, 6560),
  (800000, 899999, 7800), (900000, 1000000, 8508), (1000001, 3000000, 9346),
  (3000001, 5000000, 9890),
];

// ─── Flow Node Card ───

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
                  width: 56, height: 56,
                  transform: Matrix4.identity()..scale(pulse),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [node.color.withValues(alpha: 0.85), node.color],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    boxShadow: [BoxShadow(color: node.color.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4))],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(node.icon, color: Colors.white, size: 24),
                      Positioned(
                        right: 2, bottom: 2,
                        child: Container(
                          width: 18, height: 18,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surface, border: Border.all(color: node.color, width: 2)),
                          child: Center(child: Text('$stepNum', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: node.color))),
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
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [node.color.withValues(alpha: 0.7), flowNodes[index + 1].color.withValues(alpha: 0.25)],
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
                border: Border.all(color: node.color.withValues(alpha: 0.15), width: 0.5),
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
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: node.color.withValues(alpha: 0.15),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(node.icon, size: 12, color: node.color),
                                const SizedBox(width: 5),
                                Text(flowLabels[index], style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: node.color, letterSpacing: 0.6)),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: node.color.withValues(alpha: 0.1),
                              border: Border.all(color: node.color.withValues(alpha: 0.25), width: 0.5),
                            ),
                            child: Text(phaseLabels[index], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: node.color, letterSpacing: 0.8)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.tr(node.titleKey),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cs.onSurface, height: 1.2),
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
          Expanded(child: Text(left, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.8)))),
          Text(right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
