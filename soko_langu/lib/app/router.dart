import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/product_model.dart';
import '../screens/auth/auth_gate.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/verify_email_screen.dart';
import '../screens/home/product_detail.dart';
import '../screens/home/search_screen.dart';
import '../screens/home/checkout_screen.dart';
import '../screens/home/category_screen.dart';
import '../screens/home/category_products_screen.dart';
import '../screens/home/add_product_screen.dart';
import '../screens/home/discovery_screen.dart';
import '../screens/chat/chat_page.dart';
import '../screens/chat/chats_list_screen.dart';
import '../screens/chat/create_group_screen.dart';
import '../screens/chat/group_chat_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/profile/public_profile_screen.dart';
import '../screens/profile/settings_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/shop_customization_screen.dart';
import '../screens/profile/wishlist_screen.dart';
import '../screens/profile/my_ads_screen.dart';
import '../screens/profile/seller_dashboard_screen.dart';
import '../screens/profile/product_boost_screen.dart';
import '../screens/profile/help_center_screen.dart';
import '../screens/profile/about_app_screen.dart';
import '../screens/notification/notification_screen.dart';
import '../screens/audio/audio_player_screen.dart';
import '../screens/audio/audio_list_screen.dart';
import '../screens/audio/audio_queue_screen.dart';
import '../screens/onboarding/account_selection_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';

import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_ad_revenue_screen.dart';
import '../screens/admin/admin_wallet_screen.dart';
import '../screens/seller/seller_earnings_screen.dart';
import '../screens/orders/my_purchases_screen.dart';
import '../screens/kyc/kyc_screen.dart';
import '../screens/home/flash_sale_screen.dart';
import '../screens/profile/create_flash_sale_screen.dart';
import '../screens/report/report_screen.dart';
import '../screens/report/admin_reports_screen.dart';
import '../screens/ai/ai_assistant_screen.dart';

import '../screens/legal/privacy_policy_screen.dart';
import '../screens/legal/terms_of_service_screen.dart';
import '../models/status_model.dart';
import '../screens/status/status_list_screen.dart';
import '../screens/status/status_viewer_screen.dart';
import '../screens/status/add_status_screen.dart';
import 'routes.dart';
import 'app_state.dart' as app_state;

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.home,
    redirect: (context, state) {
      if (!app_state.onboardingSeen && state.uri.path != AppRoutes.onboarding && state.uri.path != AppRoutes.login && state.uri.path != AppRoutes.register) {
        return AppRoutes.onboarding;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const AuthGate(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (context, state) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: AppRoutes.accountSelection,
        builder: (context, state) => const AccountSelectionScreen(),
      ),
      GoRoute(
        path: AppRoutes.chats,
        builder: (context, state) => const ChatsListScreen(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const ProfilePage(),
      ),
      GoRoute(
        path: '${AppRoutes.productDetail}/:id',
        builder: (context, state) {
          return ProductDetailPage(product: state.extra as Product);
        },
      ),
      GoRoute(
        path: '${AppRoutes.chat}/:receiverId',
        builder: (context, state) {
          final receiverId = state.pathParameters['receiverId']!;
          final extra = state.extra as Map<String, String>?;
          return ChatPage(
            receiverId: receiverId,
            receiverName: extra?['name'] ?? '',
            productName: extra?['product'] ?? '',
          );
        },
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.publicProfile}/:userId',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          final name = state.extra as String? ?? '';
          return PublicProfileScreen(userId: userId, userName: name);
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.sellerDashboard,
        builder: (context, state) => const SellerDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.search,
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.category,
        builder: (context, state) => const CategoryScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.categoryProducts}/:name',
        builder: (context, state) {
          return CategoryProductsScreen(category: state.extra as dynamic);
        },
      ),
      GoRoute(
        path: AppRoutes.editProfile,
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.shopCustomization,
        builder: (context, state) => const ShopCustomizationScreen(),
      ),
      GoRoute(
        path: AppRoutes.wishlist,
        builder: (context, state) => const WishlistScreen(),
      ),
      GoRoute(
        path: AppRoutes.myAds,
        builder: (context, state) => const MyAdsScreen(),
      ),
      GoRoute(
        path: AppRoutes.help,
        builder: (context, state) => const HelpCenterScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (context, state) => const AboutAppScreen(),
      ),
      GoRoute(
        path: AppRoutes.addProduct,
        builder: (context, state) {
          return AddProductScreen(product: state.extra as dynamic);
        },
      ),
      GoRoute(
        path: AppRoutes.audioList,
        builder: (context, state) => const AudioListScreen(),
      ),
      GoRoute(
        path: AppRoutes.audioQueue,
        builder: (context, state) => const AudioQueueScreen(),
      ),
      GoRoute(
        path: AppRoutes.audioPlayer,
        builder: (context, state) {
          final extra = state.extra as Map?;
          return AudioPlayerScreen(
            audioUrl: extra?['url'] as String?,
            title: extra?['title'] as String?,
            artist: extra?['artist'] as String?,
            urls: extra?['urls'] is List ? (extra!['urls'] as List<String>) : null,
            titles: extra?['titles'] is List ? (extra!['titles'] as List<String>) : null,
            artists: extra?['artists'] is List ? (extra!['artists'] as List<String>) : null,
            imageUrls: extra?['imageUrls'] is List ? (extra!['imageUrls'] as List<String>) : null,
            initialIndex: extra?['initialIndex'] as int? ?? 0,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.admin,
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminAdRevenue,
        builder: (context, state) => const AdminAdRevenueScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminWallet,
        builder: (context, state) => const AdminWalletScreen(),
      ),
      GoRoute(
        path: AppRoutes.createGroup,
        builder: (context, state) => const CreateGroupScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.groupChat}/:groupId',
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return GroupChatScreen(groupId: groupId);
        },
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),

      GoRoute(
        path: AppRoutes.status,
        builder: (context, state) => const StatusListScreen(),
      ),
      GoRoute(
        path: AppRoutes.statusViewer,
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>;
          return StatusViewerScreen(
            updates: (data['updates'] as List).cast<StatusUpdate>(),
            initialIndex: data['initialIndex'] as int? ?? 0,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.addStatus,
        builder: (context, state) => const AddStatusScreen(),
      ),
      GoRoute(
        path: AppRoutes.aiAssistant,
        builder: (context, state) => const AiAssistantScreen(),
      ),
      GoRoute(
        path: AppRoutes.sellerEarnings,
        builder: (context, state) => const SellerEarningsScreen(),
      ),
      GoRoute(
        path: AppRoutes.checkout,
        builder: (context, state) => CheckoutScreen(product: state.extra as dynamic),
      ),
      GoRoute(
        path: AppRoutes.productBoost,
        builder: (context, state) => ProductBoostScreen(product: state.extra as dynamic),
      ),
      GoRoute(
        path: AppRoutes.discovery,
        builder: (context, state) => const DiscoveryScreen(),
      ),
      GoRoute(
        path: AppRoutes.myPurchases,
        builder: (context, state) => const MyPurchasesScreen(),
      ),
      GoRoute(
        path: AppRoutes.kyc,
        builder: (context, state) => const KycScreen(),
      ),
      GoRoute(
        path: AppRoutes.report,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return ReportScreen(
            reportedUserId: extra['reportedUserId'] as String,
            reportedUserName: extra['reportedUserName'] as String,
            productId: extra['productId'] as String?,
            productName: extra['productName'] as String?,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.adminReports,
        builder: (context, state) => const AdminReportsScreen(),
      ),
      GoRoute(
        path: AppRoutes.flashSale,
        builder: (context, state) => const FlashSaleScreen(),
      ),
      GoRoute(
        path: AppRoutes.createFlashSale,
        builder: (context, state) => const CreateFlashSaleScreen(),
      ),
      GoRoute(
        path: AppRoutes.privacyPolicy,
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: AppRoutes.termsOfService,
        builder: (context, state) => const TermsOfServiceScreen(),
      ),
    ],
  );
}
