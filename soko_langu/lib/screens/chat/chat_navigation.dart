import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/chat_service.dart';

class ChatNavigation {
  static Future<void> openSellerChat(BuildContext context, String sellerId, String sellerName) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await ChatService().getOrCreateRoom(otherUserId: sellerId);
    if (context.mounted) {
      context.push('/chat/$sellerId', extra: {'name': sellerName});
    }
  }
}
