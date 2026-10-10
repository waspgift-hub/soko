import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiBase = String.fromEnvironment('SOKO_WALLET_API', defaultValue: '');
const green = Color(0xFF0B8F55);
const green2 = Color(0xFF19B96F);

void main() => runApp(const SokoWallet());

class SokoWallet extends StatelessWidget {
  const SokoWallet({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, title: 'Soko Vibe Wallet',
      theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: green), scaffoldBackgroundColor: Colors.white),
      home: const WalletPage());
  }
}

class WalletPage extends StatefulWidget { const WalletPage({super.key}); @override State<WalletPage> createState()=>_WalletPageState(); }
class _WalletPageState extends State<WalletPage> {
  int tab=0, balance=0; bool loading=false; String provider='M-Pesa', status='';
  final amount=TextEditingController(), phone=TextEditingController();
  @override void initState(){super.initState(); refresh();}
  @override void dispose(){amount.dispose();phone.dispose();super.dispose();}
  Future<void> refresh() async { if(apiBase.isEmpty)return; try{final r=await http.get(Uri.parse('$apiBase/wallet/balance')).timeout(const Duration(seconds:8)); if(r.statusCode==200&&mounted){final d=jsonDecode(r.body);setState(()=>balance=(d['balance'] as num?)?.toInt()??0);}}catch(_){} }
  Future<void> deposit() async {
    final a=int.tryParse(amount.text.replaceAll(',','').trim()); final p=phone.text.trim();
    if(a==null||a<500||p.length<9){setState(()=>status='Weka kiasi kuanzia TZS 500 na namba sahihi.');return;}
    if(apiBase.isEmpty){setState(()=>status='Backend haijawekwa kwenye build hii.');return;}
    setState(()=>loading=true);
    try{final r=await http.post(Uri.parse('$apiBase/wallet/deposit'),headers:{'Content-Type':'application/json'},body:jsonEncode({'amount':a,'phone':p,'provider':provider})).timeout(const Duration(seconds:15));final d=jsonDecode(r.body);if(r.statusCode<200||r.statusCode>=300)throw Exception(d['error']??'Payment failed');if(mounted){Navigator.pop(context);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(d['message']??'Payment request sent')));await refresh();}}catch(e){if(mounted)setState(()=>status='Malipo hayajaanza: ${e.toString().replaceFirst('Exception: ','')}');}finally{if(mounted)setState(()=>loading=false);}
  }
  void addMoney(){amount.clear();phone.clear();status='';showModalBottomSheet(context:context,isScrollControlled:true,showDragHandle:true,builder:(_)=>StatefulBuilder(builder:(c,setSheet)=>Padding(padding:EdgeInsets.fromLTRB(20,4,20,MediaQuery.of(c).viewInsets.bottom+20),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Add Money',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w800)),const SizedBox(height:6),const Text('Weka fedha kwenye Soko Vibe Wallet.'),const SizedBox(height:16),TextField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Amount (TZS)',prefixText:'TZS ',border:OutlineInputBorder())),const SizedBox(height:12),TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Mobile number',hintText:'07XXXXXXXX',border:OutlineInputBorder())),const SizedBox(height:12),Wrap(spacing:7,children:['M-Pesa','Airtel Money','Mixx by Yas','HaloPesa'].map((x)=>ChoiceChip(label:Text(x),selected:provider==x,onSelected:(_)=>setSheet(()=>provider=x))).toList()),if(status.isNotEmpty)Padding(padding:const EdgeInsets.only(top:10),child:Text(status,style:TextStyle(color:Theme.of(c).colorScheme.error))),const SizedBox(height:15),SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:loading?null:deposit,icon:loading?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.lock_rounded),label:Text(loading?'Processing…':'Continue to payment')))]))));}
  @override Widget build(BuildContext context){final pages=[home(),history(),settings()];return Scaffold(appBar:AppBar(title:const Text('My Wallet',style:TextStyle(fontWeight:FontWeight.w800)),actions:[IconButton(onPressed:refresh,icon:const Icon(Icons.refresh_rounded))]),body:pages[tab],bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const[NavigationDestination(icon:Icon(Icons.account_balance_wallet_outlined),selectedIcon:Icon(Icons.account_balance_wallet),label:'Wallet'),NavigationDestination(icon:Icon(Icons.receipt_long_outlined),selectedIcon:Icon(Icons.receipt_long),label:'History'),NavigationDestination(icon:Icon(Icons.settings_outlined),selectedIcon:Icon(Icons.settings),label:'Settings') ]));}
  Widget home()=>RefreshIndicator(onRefresh:refresh,child:ListView(padding:const EdgeInsets.all(18),children:[Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(borderRadius:BorderRadius.circular(28),gradient:const LinearGradient(colors:[green,green2])),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Row(children:[Icon(Icons.verified_user_rounded,color:Colors.white70),SizedBox(width:7),Text('Secure wallet',style:TextStyle(color:Colors.white70,fontWeight:FontWeight.w600))]),const SizedBox(height:22),const Text('Available balance',style:TextStyle(color:Colors.white70)),Text('TZS ${money(balance)}',style:const TextStyle(color:Colors.white,fontSize:31,fontWeight:FontWeight.w900)),const SizedBox(height:18),Row(children:[Expanded(child:FilledButton.tonalIcon(onPressed:addMoney,icon:const Icon(Icons.add),label:const Text('Add Money'))),const SizedBox(width:10),Expanded(child:OutlinedButton.icon(onPressed:()=>msg('Send Money itawashwa baada ya payout API kuthibitishwa.'),icon:const Icon(Icons.arrow_upward),label:const Text('Send Money'),style:OutlinedButton.styleFrom(foregroundColor:Colors.white,side:const BorderSide(color:Colors.white54))))])])),const SizedBox(height:22),Text('Quick actions',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w800)),const SizedBox(height:10),Row(children:[action(Icons.phone_android,'Mobile Money',addMoney),action(Icons.receipt_long,'Transactions',()=>setState(()=>tab=1)),action(Icons.security,'Security',()=>msg('Wallet operations are verified server-side.'))]),const SizedBox(height:22),Text('Recent activity',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w800)),const Card(child:ListTile(leading:Icon(Icons.account_balance_wallet),title:Text('Wallet ready'),subtitle:Text('No completed transactions yet')))]));
  Widget action(IconData i,String t,VoidCallback f)=>Expanded(child:InkWell(onTap:f,borderRadius:BorderRadius.circular(20),child:Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Column(children:[Container(width:52,height:52,decoration:BoxDecoration(color:Theme.of(context).colorScheme.primaryContainer,borderRadius:BorderRadius.circular(17)),child:Icon(i,color:green)),const SizedBox(height:6),Text(t,textAlign:TextAlign.center,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700))]))));
  Widget history()=>ListView(padding:const EdgeInsets.all(18),children:[Text('Transactions',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w800)),const SizedBox(height:8),const Card(child:ListTile(leading:Icon(Icons.info_outline),title:Text('No transactions yet'),subtitle:Text('Completed payments will appear here.')))]);
  Widget settings()=>ListView(padding:const EdgeInsets.all(18),children:[Text('Wallet settings',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w800)),const SizedBox(height:12),const Card(child:Column(children:[ListTile(leading:Icon(Icons.lock_outline),title:Text('Secure payments'),subtitle:Text('Payment credentials never live in the APK.')),Divider(height:1),ListTile(leading:Icon(Icons.privacy_tip_outlined),title:Text('Privacy'),subtitle:Text('Only required payment data is sent to the server.'))]))]);
  void msg(String x)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(x)));
  String money(int n)=>n.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'),(_)=>',');
}
