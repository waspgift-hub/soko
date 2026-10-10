import 'package:flutter/material.dart';

const green = Color(0xFF0B7A4B);
const pale = Color(0xFFEAF6F1);
const ink = Color(0xFF111111);

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Soko Vibe Premium',
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: green), scaffoldBackgroundColor: Colors.white),
      home: const SubscriptionFlow(),
    );
  }
}

class SvLogo extends StatelessWidget {
  const SvLogo({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 38, height: 38,
    decoration: BoxDecoration(border: Border.all(color: ink, width: 1.8), borderRadius: BorderRadius.circular(11)),
    alignment: Alignment.center,
    child: const Text('SV', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: -1.5)),
  );
}

class SubscriptionFlow extends StatefulWidget {
  const SubscriptionFlow({super.key});
  @override
  State<SubscriptionFlow> createState() => _SubscriptionFlowState();
}

class _SubscriptionFlowState extends State<SubscriptionFlow> {
  int step = 0;
  String plan = 'Seller Plus';
  int price = 14900;
  String paymentMethod = 'M-Pesa';

  void next() => setState(() => step = step < 7 ? step + 1 : 0);
  void previous() => setState(() => step = step > 0 ? step - 1 : 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: step == 0 ? null : IconButton(onPressed: previous, icon: const Icon(Icons.arrow_back_rounded)),
        title: const Row(children: [SvLogo(), SizedBox(width: 10), Text('Soko Vibe', style: TextStyle(color: ink, fontWeight: FontWeight.w900))]),
        actions: [Padding(padding: const EdgeInsets.only(right: 18), child: Center(child: Text('${step + 1}/8', style: const TextStyle(color: green, fontWeight: FontWeight.w800))))],
      ),
      body: Column(children: [
        LinearProgressIndicator(value: (step + 1) / 8, minHeight: 3, backgroundColor: const Color(0xFFE8E8E8), valueColor: const AlwaysStoppedAnimation(green)),
        Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: buildScreen())),
      ]),
    );
  }

  Widget shell(Widget content, String actionText, VoidCallback action) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(22, 28, 22, 30),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [content, const SizedBox(height: 24), SizedBox(width: double.infinity, height: 55, child: FilledButton(onPressed: action, style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))), child: Text(actionText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))))]),
  );

  Widget buildScreen() {
    switch (step) {
      case 0: return shell(intro(), 'Angalia Plans', next);
      case 1: return shell(plans(), 'Endelea na $plan', next);
      case 2: return shell(details(), 'Endelea kulipa', next);
      case 3: return shell(methods(), 'Endelea', next);
      case 4: return shell(confirm(), 'Lipa TZS ${money(price)}', next);
      case 5: return shell(processing(), 'Demo: Malipo yamefanikiwa', next);
      case 6: return shell(success(), 'Simamia Subscription', next);
      default: return shell(manage(), 'Rudi mwanzo', () => setState(() => step = 0));
    }
  }

  Widget intro() => Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
    const SizedBox(height: 25),
    Container(width: 116, height: 116, decoration: BoxDecoration(color: pale, borderRadius: BorderRadius.circular(36)), child: const Icon(Icons.workspace_premium_rounded, color: green, size: 60)),
    const SizedBox(height: 25),
    const Text('Soko Vibe Premium', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: ink)),
    const SizedBox(height: 10),
    const Text('Uwezo zaidi wa kuuza, kukua na kutumia Soko Vibe kwa nguvu zaidi.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 16, height: 1.45)),
    const SizedBox(height: 28),
    benefit(Icons.auto_awesome, 'AI zaidi kwa biashara yako'),
    benefit(Icons.insights_rounded, 'Seller analytics na tools'),
    benefit(Icons.block_rounded, 'Hakuna matangazo'),
    benefit(Icons.flash_on_rounded, 'Priority features'),
  ]);

  Widget benefit(IconData icon, String text) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [Container(width: 43, height: 43, decoration: BoxDecoration(color: pale, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: green, size: 21)), const SizedBox(width: 12), Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)))]));

  Widget plans() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Chagua plan yako', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink)),
    const SizedBox(height: 7), const Text('Chagua inayolingana na biashara yako.', style: TextStyle(color: Colors.black54)), const SizedBox(height: 22),
    planCard('Seller Plus', 14900, '50 AI actions / siku'),
    planCard('Seller Pro', 29900, '200 AI actions / siku'),
    planCard('Business', 79900, '500 AI actions / siku', featured: true),
  ]);

  Widget planCard(String title, int amount, String sub, {bool featured = false}) {
    final selected = plan == title;
    return GestureDetector(
      onTap: () => setState(() { plan = title; price = amount; }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 13), padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(color: selected ? pale : Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: selected ? green : const Color(0xFFD8D8D8), width: selected ? 2 : 1)),
        child: Row(children: [
          CircleAvatar(backgroundColor: selected ? green : const Color(0xFFF1F1F1), child: Icon(Icons.workspace_premium, color: selected ? Colors.white : ink)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), if (featured) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(99)), child: const Text('BEST', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900))]]),
            const SizedBox(height: 5), Text(sub, style: const TextStyle(color: Colors.black54)), const SizedBox(height: 7), Text('TZS ${money(amount)}', style: const TextStyle(color: green, fontWeight: FontWeight.w900, fontSize: 18)),
          ])),
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? green : Colors.black26),
        ]),
      ),
    );
  }

  Widget details() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Maelezo ya plan', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink)), const SizedBox(height: 20),
    Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(24)), child: Row(children: [const CircleAvatar(radius: 26, backgroundColor: green, child: Icon(Icons.workspace_premium, color: Colors.white)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(plan, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text('TZS ${money(price)}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900))]))])),
    const SizedBox(height: 22), const Text('Kinachojumuishwa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 12),
    check('AI quota kulingana na plan'), check('No ads'), check('Seller analytics'), check('Priority support'), check('Premium seller tools'),
  ]);

  Widget check(String text) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [const Icon(Icons.check_circle, color: green), const SizedBox(width: 10), Text(text, style: const TextStyle(fontWeight: FontWeight.w600))]));

  Widget methods() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Njia ya malipo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink)), const SizedBox(height: 8), const Text('Chagua njia ya malipo unayotaka.', style: TextStyle(color: Colors.black54)), const SizedBox(height: 22),
    paymentCard('M-Pesa', Icons.phone_android), paymentCard('Airtel Money', Icons.phone_iphone), paymentCard('Mixx by Yas', Icons.account_balance_wallet), paymentCard('HaloPesa', Icons.payments_outlined),
  ]);

  Widget paymentCard(String name, IconData icon) {
    final selected = paymentMethod == name;
    return GestureDetector(onTap: () => setState(() => paymentMethod = name), child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: selected ? pale : Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: selected ? green : const Color(0xFFD8D8D8), width: selected ? 2 : 1)), child: Row(children: [CircleAvatar(backgroundColor: selected ? green : const Color(0xFFF2F2F2), child: Icon(icon, color: selected ? Colors.white : ink)), const SizedBox(width: 12), Expanded(child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))), Icon(selected ? Icons.check_circle : Icons.radio_button_off, color: selected ? green : Colors.black26)])));
  }

  Widget confirm() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Thibitisha malipo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink)), const SizedBox(height: 22),
    summaryRow('Plan', plan), summaryRow('Bei', 'TZS ${money(price)}'), summaryRow('Malipo kupitia', paymentMethod), const Divider(height: 30), summaryRow('Jumla', 'TZS ${money(price)}', strong: true), const SizedBox(height: 20),
    Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0xFFFFF8DD), borderRadius: BorderRadius.circular(15)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.info_outline), SizedBox(width: 9), Expanded(child: Text('Demo hii inaonyesha UI ya payment flow. Gateway halisi itaunganishwa baadaye.'))])),
  ]);

  Widget summaryRow(String label, String value, {bool strong = false}) => Padding(padding: const EdgeInsets.only(bottom: 16), child: Row(children: [Expanded(child: Text(label, style: const TextStyle(color: Colors.black54))), Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: strong ? 20 : 15, color: strong ? green : ink))]));

  Widget processing() => Column(crossAxisAlignment: CrossAxisAlignment.center, children: [const SizedBox(height: 85), Container(width: 112, height: 112, decoration: const BoxDecoration(color: pale, shape: BoxShape.circle), padding: const EdgeInsets.all(27), child: const CircularProgressIndicator(color: green, strokeWidth: 5)), const SizedBox(height: 28), const Text('Inathibitisha malipo...', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: ink)), const SizedBox(height: 10), const Text('Tafadhali subiri. Usifunge app.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54))]);

  Widget success() => Column(crossAxisAlignment: CrossAxisAlignment.center, children: [const SizedBox(height: 55), Container(width: 112, height: 112, decoration: const BoxDecoration(color: green, shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Colors.white, size: 66)), const SizedBox(height: 25), const Text('Malipo yamefanikiwa!', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink)), const SizedBox(height: 9), Text('$plan imewezeshwa kwenye akaunti yako.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, fontSize: 16)), const SizedBox(height: 24), info('Transaction ID', 'SV-2026-001248'), info('Kiasi', 'TZS ${money(price)}'), info('Status', 'ACTIVE')]);

  Widget info(String label, String value) => Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13), decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(13)), child: Row(children: [Expanded(child: Text(label, style: const TextStyle(color: Colors.black54))), Text(value, style: const TextStyle(fontWeight: FontWeight.w800))]));

  Widget manage() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Subscription yako', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: ink)), const SizedBox(height: 18),
    Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(24)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(plan, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 6), Text('TZS ${money(price)} / mwezi', style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900)), const SizedBox(height: 12), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(99)), child: const Text('ACTIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)))])),
    const SizedBox(height: 15), info('Inaanza', '10 Oct 2026'), info('Inaisha', '10 Nov 2026'), info('Auto-renew', 'Imewashwa'),
  ]);
}

String money(int value) => value.toString().replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+$)'), (_) => ',');
