import 'package:flutter/material.dart';

/// Soko Vibe subscription/payment UI prototype.
///
/// This is intentionally UI-only: payment provider integration is not performed here.
class SubscriptionDemoScreen extends StatefulWidget {
  const SubscriptionDemoScreen({super.key});

  @override
  State<SubscriptionDemoScreen> createState() => _SubscriptionDemoScreenState();
}

class _SubscriptionDemoScreenState extends State<SubscriptionDemoScreen> {
  static const green = Color(0xFF0B7A4B);
  static const paleGreen = Color(0xFFEAF6F1);
  static const ink = Color(0xFF111111);

  int _step = 0;
  String _plan = 'Seller Plus';
  int _price = 14900;
  String _method = 'M-Pesa';

  String get _stepTitle => const [
        'Soko Vibe Premium',
        'Chagua plan yako',
        'Maelezo ya plan',
        'Njia ya malipo',
        'Thibitisha malipo',
        'Inathibitisha...',
        'Malipo yamefanikiwa',
        'Usimamizi wa plan',
      ][_step];

  void _go(int step) => setState(() => _step = step);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: ink),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: ink, width: 1.5),
              ),
              alignment: Alignment.center,
              child: const Text('SV', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            const Text('Soko Vibe', style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('${_step + 1}/8', style: const TextStyle(color: green, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_step + 1) / 8,
              minHeight: 3,
              backgroundColor: const Color(0xFFE8E8E8),
              valueColor: const AlwaysStoppedAnimation(green),
            ),
            Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: _body())),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case 0: return _intro();
      case 1: return _plans();
      case 2: return _details();
      case 3: return _paymentMethod();
      case 4: return _confirm();
      case 5: return _processing();
      case 6: return _success();
      default: return _manage();
    }
  }

  Widget _page({required Widget child, Widget? bottom}) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [child, if (bottom != null) ...[const SizedBox(height: 22), bottom]]),
      );

  Widget _intro() => _page(
        child: Column(
          children: [
            const SizedBox(height: 22),
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(color: paleGreen, borderRadius: BorderRadius.circular(34)),
              child: const Icon(Icons.workspace_premium_rounded, size: 58, color: green),
            ),
            const SizedBox(height: 26),
            const Text('Soko Vibe Premium', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: ink)),
            const SizedBox(height: 12),
            const Text('Fungua uwezo zaidi wa kuuza, kukua na kutumia Soko Vibe kwa nguvu zaidi.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, height: 1.5, color: Colors.black54)),
            const SizedBox(height: 28),
            _benefit(Icons.auto_awesome, 'AI zaidi kwa biashara yako'),
            _benefit(Icons.insights_rounded, 'Analytics na tools za seller'),
            _benefit(Icons.block_rounded, 'Hakuna matangazo kwenye plan za kulipia'),
            _benefit(Icons.flash_on_rounded, 'Priority features'),
          ],
        ),
        bottom: _button('Angalia Plans', () => _go(1)),
      );

  Widget _benefit(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: paleGreen, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: green, size: 21)),
          const SizedBox(width: 13),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
        ]),
      );

  Widget _plans() => _page(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Chagua plan yako', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink)),
          const SizedBox(height: 7),
          const Text('Unaweza kubadilisha plan wakati wowote.', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 22),
          _planCard('Seller Plus', 'TZS 14,900', '50 AI actions / siku', _plan == 'Seller Plus', () { setState(() { _plan = 'Seller Plus'; _price = 14900; }); }),
          _planCard('Seller Pro', 'TZS 29,900', '200 AI actions / siku', _plan == 'Seller Pro', () { setState(() { _plan = 'Seller Pro'; _price = 29900; }); }),
          _planCard('Business', 'TZS 79,900', '500 AI actions / siku', _plan == 'Business', () { setState(() { _plan = 'Business'; _price = 79900; }); }, featured: true),
        ]),
        bottom: _button('Endelea na $_plan', () => _go(2)),
      );

  Widget _planCard(String title, String price, String sub, bool selected, VoidCallback onTap, {bool featured = false}) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected ? paleGreen : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: selected ? green : const Color(0xFFDADADA), width: selected ? 2 : 1),
          ),
          child: Row(children: [
            Container(width: 50, height: 50, decoration: BoxDecoration(color: selected ? green : const Color(0xFFF2F2F2), shape: BoxShape.circle), child: Icon(Icons.workspace_premium, color: selected ? Colors.white : Colors.black54)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), if (featured) ...[const SizedBox(width: 8), _pill('BEST')]]),
              const SizedBox(height: 5),
              Text(sub, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              Text(price, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: green)),
            ])),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? green : Colors.black26),
          ]),
        ),
      );

  Widget _pill(String text) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(99)), child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)));

  Widget _details() => _page(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Maelezo ya plan', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink)),
          const SizedBox(height: 20),
          _summaryCard(),
          const SizedBox(height: 20),
          const Text('Kinachojumuishwa', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 12),
          ...['AI quota kulingana na plan', 'No ads', 'Seller analytics', 'Priority support', 'Premium seller tools'].map((x) => _checkRow(x)),
        ]),
        bottom: _button('Endelea kulipa', () => _go(3)),
      );

  Widget _summaryCard() => Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(25)), child: Row(children: [
        const CircleAvatar(radius: 26, backgroundColor: green, child: Icon(Icons.workspace_premium, color: Colors.white)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_plan, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text('TZS ${_price.toString().replaceAllMapped(RegExp(r'(?=(\\d{3})+(?!\\d))'), (m) => ',')}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900))]),),
      ]));

  Widget _checkRow(String text) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [const Icon(Icons.check_circle, color: green, size: 22), const SizedBox(width: 10), Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))]));

  Widget _paymentMethod() => _page(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Njia ya malipo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink)),
          const SizedBox(height: 8),
          const Text('Chagua njia unayotaka kutumia kulipia subscription.', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 22),
          _methodCard('M-Pesa', Icons.phone_android, 'Vodacom M-Pesa'),
          _methodCard('Airtel Money', Icons.phone_iphone, 'Airtel Money'),
          _methodCard('Mixx by Yas', Icons.account_balance_wallet, 'Mixx by Yas'),
          _methodCard('HaloPesa', Icons.payments_outlined, 'HaloPesa'),
        ]),
        bottom: _button('Endelea', () => _go(4)),
      );

  Widget _methodCard(String title, IconData icon, String subtitle) {
    final selected = _method == title;
    return GestureDetector(onTap: () => setState(() => _method = title), child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(17), decoration: BoxDecoration(color: selected ? paleGreen : Colors.white, borderRadius: BorderRadius.circular(19), border: Border.all(color: selected ? green : const Color(0xFFDADADA), width: selected ? 2 : 1)), child: Row(children: [CircleAvatar(backgroundColor: selected ? green : const Color(0xFFF1F1F1), child: Icon(icon, color: selected ? Colors.white : ink)), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 13))])), Icon(selected ? Icons.check_circle : Icons.radio_button_off, color: selected ? green : Colors.black26)])));
  }

  Widget _confirm() => _page(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Thibitisha malipo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink)),
          const SizedBox(height: 20),
          _line('Plan', _plan),
          _line('Bei', 'TZS ${_price.toString()}'),
          _line('Malipo kupitia', _method),
          const Divider(height: 32),
          _line('Jumla', 'TZS ${_price.toString()}', strong: true),
          const SizedBox(height: 24),
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFFFF9E6), borderRadius: BorderRadius.circular(16)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.info_outline, color: Colors.black87), SizedBox(width: 10), Expanded(child: Text('Hii ni demo ya UI. Payment gateway halijaunganishwa kwenye screen hii.', style: TextStyle(height: 1.4)))])),
        ]),
        bottom: _button('Lipa TZS ${_price.toString()}', () => _go(5)),
      );

  Widget _line(String label, String value, {bool strong = false}) => Padding(padding: const EdgeInsets.only(bottom: 17), child: Row(children: [Expanded(child: Text(label, style: TextStyle(color: Colors.black54, fontSize: 14))), Text(value, style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w700, fontSize: strong ? 20 : 15, color: strong ? green : ink))]));

  Widget _processing() => _page(child: Center(child: Column(children: [const SizedBox(height: 100), Container(width: 110, height: 110, decoration: BoxDecoration(color: paleGreen, shape: BoxShape.circle), child: const Padding(padding: EdgeInsets.all(25), child: CircularProgressIndicator(strokeWidth: 5, color: green))), const SizedBox(height: 30), const Text('Inathibitisha malipo...', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: ink)), const SizedBox(height: 10), const Text('Tafadhali subiri. Usifunge app.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 15))])), bottom: _button('Demo: Malipo yamefanikiwa', () => _go(6)));

  Widget _success() => _page(child: Center(child: Column(children: [const SizedBox(height: 60), Container(width: 112, height: 112, decoration: const BoxDecoration(color: green, shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Colors.white, size: 64)), const SizedBox(height: 25), const Text('Malipo yamefanikiwa!', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink)), const SizedBox(height: 10), Text('$_plan imewezeshwa kwenye akaunti yako.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, fontSize: 16)), const SizedBox(height: 22), _successInfo('Transaction ID', 'SV-2026-001248'), _successInfo('Kiasi', 'TZS ${_price.toString()}'), _successInfo('Status', 'ACTIVE')]), bottom: _button('Simamia Subscription', () => _go(7)));

  Widget _successInfo(String a, String b) => Container(margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12), decoration: BoxDecoration(color: const Color(0xFFF6F6F6), borderRadius: BorderRadius.circular(13)), child: Row(children: [Expanded(child: Text(a, style: const TextStyle(color: Colors.black54))), Text(b, style: const TextStyle(fontWeight: FontWeight.w800))]));

  Widget _manage() => _page(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Subscription yako', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink)), const SizedBox(height: 18), _summaryCard(), const SizedBox(height: 20), _managementTile(Icons.calendar_today, 'Inaanza', '10 Oct 2026'), _managementTile(Icons.event_available, 'Inaisha', '10 Nov 2026'), _managementTile(Icons.autorenew, 'Auto-renew', 'Imewashwa'), const SizedBox(height: 10), OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.swap_horiz, color: green), label: const Text('Badilisha Plan', style: TextStyle(color: green, fontWeight: FontWeight.w800)), style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52), side: const BorderSide(color: green), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))))]));

  Widget _managementTile(IconData icon, String title, String value) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(15), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE0E0E0))), child: Row(children: [Icon(icon, color: green), const SizedBox(width: 12), Expanded(child: Text(title, style: const TextStyle(color: Colors.black54))), Text(value, style: const TextStyle(fontWeight: FontWeight.w800))]));

  Widget _button(String label, VoidCallback onTap) => SizedBox(width: double.infinity, height: 56, child: FilledButton(onPressed: onTap, style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))), child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))));
}
