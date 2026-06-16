import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../services/user_service.dart';
import '../../services/whatsapp_service.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';

class ChatPage extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  final String productName;

  const ChatPage({
    super.key,
    required this.receiverId,
    this.receiverName = '',
    this.productName = '',
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final UserService userService = UserService();
  UserProfile? _sellerProfile;
  bool _loading = true;
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    _loadSellerProfile();
  }

  Future<void> _loadSellerProfile() async {
    final profile = await userService.getProfile(widget.receiverId);
    if (mounted) {
      setState(() {
        _sellerProfile = profile;
        _loading = false;
      });
    }
    if (profile != null && profile.phone.isNotEmpty && !_redirected) {
      _redirected = true;
      _openWhatsApp(profile);
    }
  }

  void _openWhatsApp(UserProfile profile) {
    final message = widget.productName.isNotEmpty
        ? context.tr('whatsapp_product_inquiry')
            .replaceAll('{0}', profile.displayName)
            .replaceAll('{1}', widget.productName)
        : context.tr('whatsapp_profile_message')
            .replaceAll('{0}', profile.displayName);

    WhatsAppService().openWhatsApp(
      phoneNumber: profile.phone,
      message: message,
      onError: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('whatsapp_open_failed')),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      onFallback: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('whatsapp_fallback')),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_sellerProfile?.displayName ?? widget.receiverName),
        actions: [
          IconButton(
            icon: Icon(Icons.flag_outlined, color: Theme.of(context).colorScheme.error.withValues(alpha: 0.7)),
            onPressed: () => context.push(AppRoutes.report, extra: {
              'reportedUserId': widget.receiverId,
              'reportedUserName': widget.receiverName,
            }),
          ),
        ],
      ),
      body: _loading
          ? const GoogleLoadingPage()
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage:
                          _sellerProfile!.profileImage.isNotEmpty
                              ? CachedNetworkImageProvider(
                                  _sellerProfile!.profileImage)
                              : null,
                      child: _sellerProfile!.profileImage.isEmpty
                          ? const Icon(Icons.person, size: 50)
                          : null,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _sellerProfile?.displayName ?? widget.receiverName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_sellerProfile!.phone.isNotEmpty)
                      Text(
                        _sellerProfile!.phone,
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.whatsappGreen,
                          foregroundColor: Theme.of(context).colorScheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.chat, size: 24),
                        label: Text(
                          context.tr('send_whatsapp_message'),
                          style: const TextStyle(fontSize: 16),
                        ),
                        onPressed: () {
                          if (_sellerProfile != null) {
                            _openWhatsApp(_sellerProfile!);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.tr('contact_seller_via_whatsapp'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}


