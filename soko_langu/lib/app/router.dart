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
import '../screens/media/media_player_screen.dart';
import '../screens/media/playlists_screen.dart';
import '../screens/onboarding/account_selection_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/onboarding/welcome_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_ad_revenue_screen.dart';
import '../screens/seller/seller_earnings_screen.dart';
import '../screens/orders/my_purchases_screen.dart';
import '../screens/kyc/kyc_screen.dart';
import '../screens/home/flash_sale_screen.dart';
import '../screens/profile/create_flash_sale_screen.dart';
import '../screens/report/report_screen.dart';
import '../screens/report/admin_reports_screen.dart';
import '../screens/music/music_player_screen.dart';
import '../screens/ai/ai_assistant_screen.dart';
import '../screens/cart/cart_screen.dart';
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
      if (!app_state.onboardingSeen && state.uri.path != AppRoutes.onboarding) {
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
        path: AppRoutes.mediaPlayer,
        builder: (context, state) => const MediaPlayerScreen(),
      ),
      GoRoute(
        path: AppRoutes.playlists,
        builder: (context, state) => const PlaylistsScreen(),
      ),
      GoRoute(
        path: AppRoutes.musicPlayer,
        builder: (context, state) => const MusicPlayerScreen(),
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
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
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
        path: AppRoutes.cart,
        builder: (context, state) => const CartScreen(),
      ),
      GoRoute(
        path: AppRoutes.createFlashSale,
        builder: (context, state) => const CreateFlashSaleScreen(),
      ),
    ],
  );
}
