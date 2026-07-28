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
import '../screens/wallet/wallet_screen.dart';
import '../screens/notification/notification_screen.dart';
import '../screens/onboarding/account_selection_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/auth/magic_link_screen.dart';

import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_user_detail_screen.dart';
import '../screens/admin/admin_wallet_screen.dart';
import '../screens/seller/seller_earnings_screen.dart';
import '../screens/boost/boost_receipt_screen.dart';
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
import '../screens/seller/seller_statement_screen.dart';

import '../screens/legal/privacy_policy_screen.dart';
import '../screens/legal/terms_of_service_screen.dart';
import '../screens/ride/ride_home_screen.dart';
import '../screens/ride/ride_booking_screen.dart';
import '../screens/ride/ride_tracking_screen.dart';
import '../screens/ride/driver_home_screen.dart';
import '../screens/ride/driver_register_screen.dart';
import '../screens/ride/driver_earnings_screen.dart';
import '../screens/ride/ride_history_screen.dart';
import 'routes.dart';
import 'app_state.dart' as app_state;

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Page<T> _premiumPage<T>(Widget child) {
  return CustomTransitionPage<T>(
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.08, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: FadeTransition(
          opacity: animation,
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
  );
}

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
  // Ride-hailing routes
  AppRoutes.rideHome,
  AppRoutes.rideBooking,
  AppRoutes.rideTracking,
  AppRoutes.driverHome,
  AppRoutes.driverRegister,
  AppRoutes.driverEarnings,
  AppRoutes.rideHistory,
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
        pageBuilder: (context, state) => _premiumPage(const AuthGate()),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) => _premiumPage(const LoginScreen()),
      ),
      GoRoute(
        path: AppRoutes.register,
        pageBuilder: (context, state) => _premiumPage(const RegisterScreen()),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        pageBuilder: (context, state) => _premiumPage(const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: AppRoutes.magicLink,
        pageBuilder: (context, state) => _premiumPage(const MagicLinkScreen()),
      ),
      GoRoute(
        path: AppRoutes.accountSelection,
        pageBuilder: (context, state) => _premiumPage(const AccountSelectionScreen()),
      ),
      GoRoute(
        path: AppRoutes.chats,
        pageBuilder: (context, state) => _premiumPage(const ChatsListScreen()),
      ),
      GoRoute(
        path: AppRoutes.profile,
        pageBuilder: (context, state) => _premiumPage(const ProfilePage()),
      ),
      GoRoute(
        path: '${AppRoutes.productDetail}/:id',
        pageBuilder: (context, state) {
          return _premiumPage(ProductDetailPage(product: state.extra as Product));
        },
      ),
      GoRoute(
        path: '${AppRoutes.chat}/:receiverId',
        pageBuilder: (context, state) {
          final receiverId = state.pathParameters['receiverId']!;
          final extra = state.extra as Map<String, String>?;
          return _premiumPage(ChatPage(
            receiverId: receiverId,
            receiverName: extra?['name'] ?? '',
            productName: extra?['productTitle'] ?? extra?['product'] ?? '',
            productId: extra?['productId'],
          ));
        },
      ),
      GoRoute(
        path: AppRoutes.notifications,
        pageBuilder: (context, state) => _premiumPage(const NotificationScreen()),
      ),
      GoRoute(
        path: '${AppRoutes.publicProfile}/:userId',
        pageBuilder: (context, state) {
          final userId = state.pathParameters['userId']!;
          final name = state.extra as String? ?? '';
          return _premiumPage(PublicProfileScreen(userId: userId, userName: name));
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        pageBuilder: (context, state) => _premiumPage(const SettingsScreen()),
      ),
      GoRoute(
        path: AppRoutes.sellerDashboard,
        pageBuilder: (context, state) => _premiumPage(const SellerDashboardScreen()),
      ),
      GoRoute(
        path: AppRoutes.search,
        pageBuilder: (context, state) => _premiumPage(const SearchScreen()),
      ),
      GoRoute(
        path: AppRoutes.category,
        pageBuilder: (context, state) => _premiumPage(const CategoryScreen()),
      ),
      GoRoute(
        path: '${AppRoutes.categoryProducts}/:name',
        pageBuilder: (context, state) {
          return _premiumPage(CategoryProductsScreen(category: state.extra as dynamic));
        },
      ),
      GoRoute(
        path: AppRoutes.editProfile,
        pageBuilder: (context, state) => _premiumPage(const EditProfileScreen()),
      ),
      GoRoute(
        path: AppRoutes.shopCustomization,
        pageBuilder: (context, state) => _premiumPage(const ShopCustomizationScreen()),
      ),
      GoRoute(
        path: AppRoutes.wishlist,
        pageBuilder: (context, state) => _premiumPage(const WishlistScreen()),
      ),
      GoRoute(
        path: AppRoutes.myAds,
        pageBuilder: (context, state) => _premiumPage(const MyAdsScreen()),
      ),
      GoRoute(
        path: AppRoutes.help,
        pageBuilder: (context, state) => _premiumPage(const HelpCenterScreen()),
      ),
      GoRoute(
        path: AppRoutes.about,
        pageBuilder: (context, state) => _premiumPage(const AboutAppScreen()),
      ),
      GoRoute(
        path: AppRoutes.orderFlow,
        pageBuilder: (context, state) => _premiumPage(const OrderFlowScreen()),
      ),
      GoRoute(
        path: AppRoutes.wallet,
        pageBuilder: (context, state) => _premiumPage(const WalletScreen()),
      ),
      GoRoute(
        path: AppRoutes.addProduct,
        pageBuilder: (context, state) {
          return _premiumPage(AddProductScreen(product: state.extra as dynamic));
        },
      ),
      GoRoute(
        path: AppRoutes.admin,
        pageBuilder: (context, state) => _premiumPage(const AdminDashboardScreen()),
      ),
      GoRoute(
        path: '${AppRoutes.adminUserDetail}/:uid',
        pageBuilder: (context, state) {
          final uid = state.pathParameters['uid']!;
          return _premiumPage(AdminUserDetailScreen(uid: uid));
        },
      ),
      GoRoute(
        path: AppRoutes.adminWallet,
        pageBuilder: (context, state) => _premiumPage(const AdminWalletScreen()),
      ),
      GoRoute(
        path: AppRoutes.createGroup,
        pageBuilder: (context, state) => _premiumPage(const CreateGroupScreen()),
      ),
      GoRoute(
        path: '${AppRoutes.groupChat}/:groupId',
        pageBuilder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return _premiumPage(GroupChatScreen(groupId: groupId));
        },
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) => _premiumPage(const OnboardingScreen()),
      ),
      GoRoute(
        path: AppRoutes.aiAssistant,
        pageBuilder: (context, state) => _premiumPage(const AiAssistantScreen()),
      ),
      GoRoute(
        path: AppRoutes.sellerEarnings,
        pageBuilder: (context, state) => _premiumPage(const SellerEarningsScreen()),
      ),
      GoRoute(
        path: AppRoutes.sellerAnalytics,
        pageBuilder: (context, state) {
          final sellerId = state.extra as String? ?? FirebaseAuth.instance.currentUser?.uid ?? '';
          return _premiumPage(SellerAnalyticsScreen(sellerId: sellerId));
        },
      ),
      GoRoute(
        path: AppRoutes.checkout,
        pageBuilder: (context, state) => _premiumPage(CheckoutScreen(product: state.extra as dynamic)),
      ),
      GoRoute(
        path: AppRoutes.productBoost,
        pageBuilder: (context, state) => _premiumPage(ProductBoostScreen(product: state.extra as dynamic)),
      ),
      GoRoute(
        path: AppRoutes.boostReceipt,
        pageBuilder: (context, state) => _premiumPage(BoostReceiptScreen(data: state.extra as Map<String, dynamic>)),
      ),
      GoRoute(
        path: AppRoutes.discovery,
        pageBuilder: (context, state) => _premiumPage(const DiscoveryScreen()),
      ),
      GoRoute(
        path: AppRoutes.myPurchases,
        pageBuilder: (context, state) => _premiumPage(const MyPurchasesScreen()),
      ),
      GoRoute(
        path: '${AppRoutes.receipt}/:orderId',
        pageBuilder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return _premiumPage(ReceiptScreen(orderId: orderId));
        },
      ),
      GoRoute(
        path: '${AppRoutes.orderDetail}/:docId',
        pageBuilder: (context, state) {
          final docId = state.pathParameters['docId']!;
          final data = state.extra as Map<String, dynamic>;
          return _premiumPage(OrderDetailScreen(docId: docId, data: data));
        },
      ),
      GoRoute(
        path: AppRoutes.sellerDispatch,
        pageBuilder: (context, state) => _premiumPage(const SellerDispatchScreen()),
      ),
      GoRoute(
        path: AppRoutes.sellerQuote,
        pageBuilder: (context, state) => _premiumPage(const SellerQuoteScreen()),
      ),
      GoRoute(
        path: AppRoutes.sellerOrders,
        pageBuilder: (context, state) => _premiumPage(const SellerOrdersScreen()),
      ),
      GoRoute(
        path: AppRoutes.sellerStatement,
        pageBuilder: (context, state) {
          final sellerId = state.extra as String? ?? FirebaseAuth.instance.currentUser?.uid ?? '';
          return _premiumPage(SellerStatementScreen(sellerId: sellerId));
        },
      ),
      GoRoute(
        path: AppRoutes.kyc,
        pageBuilder: (context, state) => _premiumPage(const KycScreen()),
      ),
      GoRoute(
        path: AppRoutes.report,
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return _premiumPage(ReportScreen(
            reportedUserId: extra['reportedUserId'] as String,
            reportedUserName: extra['reportedUserName'] as String,
            productId: extra['productId'] as String?,
            productName: extra['productName'] as String?,
          ));
        },
      ),
      GoRoute(
        path: AppRoutes.adminReports,
        pageBuilder: (context, state) => _premiumPage(const AdminReportsScreen()),
      ),
      GoRoute(
        path: AppRoutes.flashSale,
        pageBuilder: (context, state) => _premiumPage(const FlashSaleScreen()),
      ),
      GoRoute(
        path: AppRoutes.createFlashSale,
        pageBuilder: (context, state) => _premiumPage(const CreateFlashSaleScreen()),
      ),
      GoRoute(
        path: AppRoutes.privacyPolicy,
        pageBuilder: (context, state) => _premiumPage(const PrivacyPolicyScreen()),
      ),
      GoRoute(
        path: AppRoutes.termsOfService,
        pageBuilder: (context, state) => _premiumPage(const TermsOfServiceScreen()),
      ),

      // 🚗 Ride-hailing routes
      GoRoute(
        path: AppRoutes.rideHome,
        pageBuilder: (context, state) => _premiumPage(const RideHomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.rideBooking,
        pageBuilder: (context, state) => _premiumPage(const RideBookingScreen()),
      ),
      GoRoute(
        path: '${AppRoutes.rideTracking}/:rideId',
        pageBuilder: (context, state) {
          final rideId = state.pathParameters['rideId']!;
          return _premiumPage(RideTrackingScreen(rideId: rideId));
        },
      ),
      GoRoute(
        path: AppRoutes.driverHome,
        pageBuilder: (context, state) => _premiumPage(const DriverHomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.driverRegister,
        pageBuilder: (context, state) => _premiumPage(const DriverRegisterScreen()),
      ),
      GoRoute(
        path: AppRoutes.driverEarnings,
        pageBuilder: (context, state) => _premiumPage(const DriverEarningsScreen()),
      ),
      GoRoute(
        path: AppRoutes.rideHistory,
        pageBuilder: (context, state) => _premiumPage(const RideHistoryScreen()),
      ),
    ],
  );
}
