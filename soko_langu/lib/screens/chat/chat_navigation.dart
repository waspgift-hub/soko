import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../repositories/chat_repository.dart';
import '../../app/routes.dart';

class ChatNavigation {
  static Future<void> openSellerChat(BuildContext context, String sellerId, String sellerName) async {
    final repo = ChatRepository();
    final uid = repo.currentUid;
    if (uid == null) return;
    final chatId = await repo.createChat(sellerId);
    if (context.mounted) {
      context.push('/chat/$chatId', extra: {'name': sellerName});
    }
  }
}
