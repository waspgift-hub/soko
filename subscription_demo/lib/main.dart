import 'package:flutter/material.dart';

// Soko Vibe Premium UI — compact release build.
const green = Color(0xFF0A8F52);
const greenDark = Color(0xFF006B3D);
const greenLight = Color(0xFFE4F7ED);
const ink = Color(0xFF101417);
const muted = Color(0xFF5C6874);

void main() => runApp(const SokoVibeApp());

class SokoVibeApp extends StatelessWidget {
  const SokoVibeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Soko Vibe Premium',
    theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: Colors.white, colorScheme: ColorScheme.fromSeed(seedColor: green)),
    home: const PremiumScreen(),
  );
}

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});
  @override State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool yearly = true;
  String selected = 'Seller Pro';
  int get monthlyPrice => selected == 'Seller Plus' ? 14900 : selected == 'Seller Pro' ? 29900 : 79900;
  int get yearlyPrice => selected == 'Seller Plus' ? 149900 : selected == 'Seller Pro' ? 299900 : 799900;

  @override
  Widget build(BuildContext context) {
    final price = yearly ? yearlyPrice : monthlyPrice;
    return Scaffold(
      body: SafeArea(child: Stack(children: [
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: GreenGlowPainter()))),
        SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 28), child: Column(children: [
          _header(), const SizedBox(height: 24), _hero(), const SizedBox(height: 25), _benefits(), const SizedBox(height: 22), _billingToggle(), const SizedBox(height: 16),
          _planCard('Seller Plus', 14900, 149900, '50 AI actions / siku'),
          _planCard('Seller Pro', 29900, 299900, '200 AI actions / siku', popular: true),
          _planCard('Business', 79900, 799900, '500 AI actions / siku'),
          const SizedBox(height: 4),
          SizedBox(width: double.infinity, height: 56, child: FilledButton.icon(onPressed: () => _showPayment(context, price), icon: const Icon(Icons.workspace_premium_rounded), label: Text('Subscribe now  •  TZS ${money(price)}'), style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)))),
          const SizedBox(height: 8), TextButton.icon(onPressed: () {}, icon: const Icon(Icons.refresh_rounded), label: const Text('Restore purchase'), style: TextButton.styleFrom(foregroundColor: green, textStyle: const TextStyle(fontWeight: FontWeight.w800))),
          const Divider(height: 26), const Text('Kwa kuendelea, unakubali Terms of Service na Privacy Policy.', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 11.5)),
        ])),
      ])),
    );
  }

  Widget _header() => Row(children: [const SvLogo(), const SizedBox(width: 10), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Soko Vibe', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: ink)), Text('Nunua • Bei Bora • Maendeleo', style: TextStyle(fontSize: 10.5, color: muted, fontWeight: FontWeight.w600))])), IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.close_rounded, size: 29, color: ink))]);

  Widget _hero() => const Column(children: [Text('Upgrade to', textAlign: TextAlign.center, style: TextStyle(fontSize: 39, height: .98, fontWeight: FontWeight.w900, color: ink, letterSpacing: -1.7)), Text('Soko Vibe Premium', textAlign: TextAlign.center, style: TextStyle(fontSize: 39, height: .98, fontWeight: FontWeight.w900, color: green, letterSpacing: -1.7)), SizedBox(height: 13), Text('Pata tools zaidi, visibility zaidi na ukue\nbiashara yako kwa Soko Vibe.', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 16, height: 1.35))]);

  Widget _benefits() => Row(children: [_benefit(Icons.verified_user_rounded, 'Verified', 'Jenga trust'), _divider(), _benefit(Icons.storefront_rounded, 'Business', 'Manage shop'), _divider(), _benefit(Icons.bar_chart_rounded, 'Analytics', 'Track growth'), _divider(), _benefit(Icons.headset_mic_rounded, 'Support', 'Priority help')]);
  Widget _benefit(IconData icon, String title, String sub) => Expanded(child: Column(children: [Container(width: 48, height: 48, decoration: const BoxDecoration(color: greenLight, shape: BoxShape.circle), child: Icon(icon, color: green, size: 25)), const SizedBox(height: 8), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: ink)), const SizedBox(height: 3), Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, color: muted))]));
  Widget _divider() => Container(width: 1, height: 70, margin: const EdgeInsets.symmetric(horizontal: 4), color: const Color(0xFFE2E7E4));

  Widget _billingToggle() => Container(height: 76, padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: const Color(0xFFF7F9F8), borderRadius: BorderRadius.circular(38), border: Border.all(color: const Color(0xFFE5EBE8))), child: Row(children: [Expanded(child: _toggle('Monthly', !yearly)), Expanded(child: Stack(clipBehavior: Clip.none, children: [_toggle('Yearly', yearly), Positioned(top: -14, right: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: greenLight, borderRadius: BorderRadius.circular(20)), child: const Text('SAVE 30%', style: TextStyle(color: greenDark, fontSize: 9, fontWeight: FontWeight.w900))))]))]));
  Widget _toggle(String title, bool active) => GestureDetector(onTap: () => setState(() => yearly = title == 'Yearly'), child: Container(height: 66, decoration: BoxDecoration(color: active ? green : Colors.transparent, borderRadius: BorderRadius.circular(33), boxShadow: active ? [BoxShadow(color: green.withOpacity(.20), blurRadius: 14, offset: const Offset(0, 6))] : null), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(title, style: TextStyle(color: active ? Colors.white : ink, fontWeight: FontWeight.w900, fontSize: 15)), const SizedBox(height: 2), Text(active ? (title == 'Yearly' ? 'TZS ${money(yearlyPrice)} / year' : 'TZS ${money(monthlyPrice)} / month') : (title == 'Yearly' ? 'TZS ${money(yearlyPrice)} / year' : 'TZS ${money(monthlyPrice)} / month'), style: TextStyle(color: active ? Colors.white : muted, fontSize: 9.5, fontWeight: FontWeight.w600))])));

  Widget _planCard(String title, int monthly, int yearlyAmount, String quota, {bool popular = false}) {
    final active = selected == title;
    final amount = yearly ? yearlyAmount : monthly;
    return GestureDetector(onTap: () => setState(() => selected = title), child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.fromLTRB(17, 17, 17, 16), decoration: BoxDecoration(color: active ? const Color(0xFFF7FCF9) : Colors.white, borderRadius: BorderRadius.circular(23), border: Border.all(color: active ? green : const Color(0xFFE2E7E4), width: active ? 2.2 : 1.2), boxShadow: active ? [BoxShadow(color: green.withOpacity(.10), blurRadius: 18, offset: const Offset(0, 7))] : null), child: Column(children: [Row(children: [Expanded(child: Text(yearly ? 'Yearly Plan' : 'Monthly Plan', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: ink))), if (popular) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(20)), child: const Text('MOST POPULAR', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)))]), const SizedBox(height: 5), Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('TZS ${money(amount)}', style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: ink)), const SizedBox(width: 5), Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(yearly ? 'per year' : 'per month', style: const TextStyle(color: muted, fontSize: 11)))]), const SizedBox(height: 10), _line('All premium features'), _line('No ads experience'), _line(quota), _line('Cancel anytime'), const SizedBox(height: 8), SizedBox(width: double.infinity, height: 46, child: active ? FilledButton(onPressed: () => _showPayment(context, amount), style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))), child: const Text('Subscribe now', style: TextStyle(fontWeight: FontWeight.w900))) : OutlinedButton(onPressed: () => setState(() => selected = title), style: OutlinedButton.styleFrom(foregroundColor: green, side: const BorderSide(color: green), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))), child: Text('Choose $title', style: const TextStyle(fontWeight: FontWeight.w800))) )])));
  }
  Widget _line(String text) => Padding(padding: const EdgeInsets.only(bottom: 7), child: Row(children: [const Icon(Icons.check_rounded, size: 18, color: green), const SizedBox(width: 7), Text(text, style: const TextStyle(color: muted, fontSize: 12.5, fontWeight: FontWeight.w600))]));

  void _showPayment(BuildContext context, int amount) => showModalBottomSheet<void>(context: context, showDragHandle: true, backgroundColor: Colors.white, isScrollControlled: true, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))), builder: (context) => Padding(padding: const EdgeInsets.fromLTRB(22, 4, 22, 25), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Thibitisha subscription', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: ink)), const SizedBox(height: 7), Text('$selected  •  TZS ${money(amount)}', style: const TextStyle(color: muted, fontWeight: FontWeight.w600)), const SizedBox(height: 18), _payOption('M-Pesa', Icons.phone_android_rounded), _payOption('Airtel Money', Icons.phone_iphone_rounded), _payOption('Mixx by Yas', Icons.account_balance_wallet_rounded), _payOption('HaloPesa', Icons.payments_rounded), const SizedBox(height: 7), SizedBox(width: double.infinity, height: 52, child: FilledButton(onPressed: () { Navigator.pop(context); _success(context, amount); }, style: FilledButton.styleFrom(backgroundColor: green), child: const Text('Endelea na malipo', style: TextStyle(fontWeight: FontWeight.w900))))])));
  Widget _payOption(String name, IconData icon) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: const Color(0xFFF7F9F8), borderRadius: BorderRadius.circular(15)), child: Row(children: [CircleAvatar(radius: 19, backgroundColor: greenLight, child: Icon(icon, color: green, size: 20)), const SizedBox(width: 11), Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800))), const Icon(Icons.chevron_right_rounded, color: muted)]));
  void _success(BuildContext context, int amount) => showDialog<void>(context: context, builder: (context) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)), content: Column(mainAxisSize: MainAxisSize.min, children: [Container(width: 72, height: 72, decoration: const BoxDecoration(color: green, shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Colors.white, size: 43)), const SizedBox(height: 17), const Text('Malipo yamefanikiwa!', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 7), Text('$selected imewezeshwa • TZS ${money(amount)}', textAlign: TextAlign.center, style: const TextStyle(color: muted)), const SizedBox(height: 17), SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context), style: FilledButton.styleFrom(backgroundColor: green), child: const Text('Done')))])));
}

class SvLogo extends StatelessWidget {
  const SvLogo({super.key});
  @override Widget build(BuildContext context) => Container(width: 45, height: 45, decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF13A964), Color(0xFF08763F)]), borderRadius: BorderRadius.circular(14)), alignment: Alignment.center, child: const Text('S', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)));
}

class GreenGlowPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) { final paint = Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE5F8EE), Color(0xFFFFFFFF), Color(0xFFF1FBF6)]).createShader(Rect.fromLTWH(0, 0, size.width, size.height)); canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint); final blob = Paint()..color = const Color(0x3313A964); canvas.drawCircle(Offset(-30, 150), 110, blob); canvas.drawCircle(Offset(size.width + 30, 245), 85, blob); }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String money(int value) => value.toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+$)'), (_) => ',');
