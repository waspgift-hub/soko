import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/chat_service.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';

class ChatNavigation {
  static Future<void> openSellerChat(
    BuildContext context,
    String sellerId,
    String sellerName, {
    String? productId,
    String? productName,
  }) async {
    final cleanSellerId = sellerId.trim();
    if (cleanSellerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('seller_unknown_error', 'Muuzaji hajulikani.'))),
      );
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('login_required_chat', 'Tafadhali ingia ili uweze kuchat.'))),
      );
      context.push(AppRoutes.login);
      return;
    }

    if (currentUser.uid == cleanSellerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('cannot_chat_with_self', 'Huwezi kuchat na wewe mwenyewe.'))),
      );
      return;
    }

    // Initialize room without hanging UI navigation on latency or rule errors
    try {
      unawaited(ChatService().getOrCreateRoom(
        otherUserId: cleanSellerId,
        productId: productId,
        productTitle: productName,
      ).catchError((e) {
        debugPrint('openSellerChat room init error (handled): $e');
        return '';
      }));
    } catch (_) {}

    if (context.mounted) {
      context.push(
        '${AppRoutes.chat}/$cleanSellerId',
        extra: <String, dynamic>{
          'name': sellerName,
          'productId': productId ?? '',
          'productTitle': productName ?? '',
        },
      );
    }
  }
}
