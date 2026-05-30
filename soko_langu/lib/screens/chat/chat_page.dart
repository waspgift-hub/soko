import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../services/user_service.dart';
import '../../services/whatsapp_service.dart';
import '../../app/routes.dart';
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
    String message;
    if (widget.productName.isNotEmpty) {
      message =
          'Habari ${profile.displayName}, nimeona bidhaa yako "${widget.productName}" kwenye Soko Langu. Naomba kujua zaidi.';
    } else {
      message =
          'Habari ${profile.displayName}, nimekuona kwenye Soko Langu na ningependa kufanya biashara na wewe.';
    }

    WhatsAppService().openWhatsApp(
      phoneNumber: profile.phone,
      message: message,
      onError: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Imeshindwa kufungua WhatsApp'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      onFallback: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('WhatsApp haipo, imefungua tovuti'),
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
            icon: Icon(Icons.flag_outlined, color: Colors.red[300]),
            onPressed: () => context.push(AppRoutes.report, extra: {
              'reportedUserId': widget.receiverId,
              'reportedUserName': widget.receiverName,
            }),
          ),
        ],
      ),
      body: _loading
          ? const GoogleLoadingPage()
          : Center(
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
                          color: Colors.grey[600],
                        ),
                      ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.chat, size: 24),
                        label: const Text(
                          'Tuma Ujumbe WhatsApp',
                          style: TextStyle(fontSize: 16),
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
                      'Wasiliana na muuzaji moja kwa moja kupitia WhatsApp',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[500],
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
