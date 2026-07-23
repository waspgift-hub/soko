import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/product_model.dart';
import '../screens/auth/auth_gate.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/forgot_password_screen.dart';

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
import '../screens/profile/order_flow_screen.dart';
import '../screens/notification/notification_screen.dart';
import '../screens/onboarding/account_selection_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/auth/magic_link_screen.dart';

import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_user_detail_screen.dart';
import '../screens/admin/admin_wallet_screen.dart';
import '../screens/seller/seller_earnings_screen.dart';
import '../screens/orders/my_purchases_screen.dart';
import '../screens/orders/seller_dispatch_screen.dart';
import '../screens/orders/seller_quote_screen.dart';
import '../screens/orders/seller_orders_screen.dart';
import '../screens/orders/receipt_screen.dart';
import '../screens/orders/order_detail_screen.dart';
import '../screens/kyc/kyc_screen.dart';
import '../screens/home/flash_sale_screen.dart';
import '../screens/profile/create_flash_sale_screen.dart';
import '../screens/report/report_screen.dart';
import '../screens/report/admin_reports_screen.dart';
import '../screens/ai/ai_assistant_screen.dart';
import '../screens/seller/seller_analytics_screen.dart';

import '../screens/legal/privacy_policy_screen.dart';
import '../screens/legal/terms_of_service_screen.dart';
import 'routes.dart';
import 'app_state.dart' as app_state;

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final List<String> _authRequiredRoutes = [
  AppRoutes.checkout,
  AppRoutes.kyc,
  AppRoutes.addProduct,
  AppRoutes.profile,
  AppRoutes.settings,
  AppRoutes.editProfile,
  AppRoutes.shopCustomization,
  AppRoutes.wishlist,
  AppRoutes.myAds,
  AppRoutes.sellerDashboard,
  AppRoutes.sellerEarnings,
  AppRoutes.sellerDispatch,
  AppRoutes.sellerQuote,
  AppRoutes.sellerOrders,
  AppRoutes.myPurchases,
  AppRoutes.productBoost,
  AppRoutes.notifications,
  AppRoutes.chats,
  AppRoutes.chat,
  AppRoutes.createGroup,
  AppRoutes.groupChat,
  AppRoutes.createFlashSale,
  AppRoutes.receipt,
  AppRoutes.orderDetail,
  AppRoutes.report,
];

final List<String> _adminOnlyRoutes = [
  AppRoutes.admin,
  AppRoutes.adminUserDetail,
  AppRoutes.adminWallet,
  AppRoutes.adminReports,
];

GoRouter buildRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.home,
    refreshListenable: app_state.appStateNotifier,
    redirect: (context, state) {
      if (!app_state.appStateNotifier.appInitialized) return null;

      final location = state.uri.toString();
      final isAuth = app_state.appStateNotifier.isAuthenticated;
      final isAdmin = app_state.appStateNotifier.isAdmin;

      // Admin-only routes
      if (_adminOnlyRoutes.any((r) => location == r || location.startsWith('$r/'))) {
        if (!isAuth) return AppRoutes.login;
        if (!isAdmin) {
          final user = FirebaseAuth.instance.currentUser;
          if (user?.email?.toLowerCase() != 'admin@soko-langu.com') {
            return AppRoutes.home;
          }
        }
      }

      // Auth-required routes
      if (_authRequiredRoutes.any((r) => location == r || location.startsWith('$r/'))) {
        if (!isAuth) return AppRoutes.login;
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
        path: AppRoutes.magicLink,
        builder: (context, state) => const MagicLinkScreen(),
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
            productName: extra?['productTitle'] ?? extra?['product'] ?? '',
            productId: extra?['productId'],
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
        path: AppRoutes.orderFlow,
        builder: (context, state) => const OrderFlowScreen(),
      ),
      GoRoute(
        path: AppRoutes.addProduct,
        builder: (context, state) {
          return AddProductScreen(product: state.extra as dynamic);
        },
      ),
      GoRoute(
        path: AppRoutes.admin,
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.adminUserDetail}/:uid',
        builder: (context, state) {
          final uid = state.pathParameters['uid']!;
          return AdminUserDetailScreen(uid: uid);
        },
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
        path: AppRoutes.aiAssistant,
        builder: (context, state) => const AiAssistantScreen(),
      ),
      GoRoute(
        path: AppRoutes.sellerEarnings,
        builder: (context, state) => const SellerEarningsScreen(),
      ),
      GoRoute(
        path: AppRoutes.sellerAnalytics,
        builder: (context, state) {
          final sellerId = state.extra as String? ?? FirebaseAuth.instance.currentUser?.uid ?? '';
          return SellerAnalyticsScreen(sellerId: sellerId);
        },
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
        path: '${AppRoutes.receipt}/:orderId',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return ReceiptScreen(orderId: orderId);
        },
      ),
      GoRoute(
        path: '${AppRoutes.orderDetail}/:docId',
        builder: (context, state) {
          final docId = state.pathParameters['docId']!;
          final data = state.extra as Map<String, dynamic>;
          return OrderDetailScreen(docId: docId, data: data);
        },
      ),
      GoRoute(
        path: AppRoutes.sellerDispatch,
        builder: (context, state) => const SellerDispatchScreen(),
      ),
      GoRoute(
        path: AppRoutes.sellerQuote,
        builder: (context, state) => const SellerQuoteScreen(),
      ),
      GoRoute(
        path: AppRoutes.sellerOrders,
        builder: (context, state) => const SellerOrdersScreen(),
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
