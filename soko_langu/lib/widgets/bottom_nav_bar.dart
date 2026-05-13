import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/cart/cart_screen.dart';
import '../screens/feed/feed_screen.dart';
import '../screens/chat/chats_list_screen.dart';
import '../extensions/context_tr.dart';
import '../main.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  int _unreadCount = 0;
  StreamSubscription? _unreadSub;

  final List<Widget> _screens = [
    const HomeScreen(),
    const FeedScreen(),
    const CartScreen(),
    const ChatsListScreen(),
    const ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    interstitialAdService.load();
    _listenUnread();
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }

  void _listenUnread() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _unreadSub = FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: user.uid)
        .snapshots()
        .listen((snap) {
          int total = 0;
          for (var doc in snap.docs) {
            final data = doc.data();
            final count = data['unreadCount'] as int? ?? 0;
            total += count;
          }
          if (mounted) setState(() => _unreadCount = total);
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index != _currentIndex) {
            interstitialAdService.show();
            interstitialAdService.load();
          }
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: context.tr('home'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.live_tv),
            label: context.tr('live_tab'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.shopping_cart),
            label: context.tr('shopping_cart'),
          ),
          BottomNavigationBarItem(
            icon: _unreadCount > 0
                ? Badge(
                    label: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      style: const TextStyle(fontSize: 10),
                    ),
                    child: const Icon(Icons.chat_bubble_outline),
                  )
                : const Icon(Icons.chat_bubble_outline),
            label: context.tr('chats'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: context.tr('profile'),
          ),
        ],
      ),
    );
  }
}
