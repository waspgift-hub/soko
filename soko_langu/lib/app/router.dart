import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/product_model.dart';
import '../services/live_stream_service.dart';
import '../screens/auth/auth_gate.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/verify_email_screen.dart';
import '../screens/home/product_detail.dart';
import '../screens/home/search_screen.dart';
import '../screens/home/category_screen.dart';
import '../screens/home/category_products_screen.dart';
import '../screens/home/add_product_screen.dart';
import '../screens/cart/cart_screen.dart';
import '../screens/chat/chat_page.dart';
import '../screens/chat/chats_list_screen.dart';
import '../screens/chat/create_group_screen.dart';
import '../screens/chat/group_chat_screen.dart';
import '../screens/feed/feed_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/profile/public_profile_screen.dart';
import '../screens/profile/settings_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/shop_customization_screen.dart';
import '../screens/profile/wishlist_screen.dart';
import '../screens/profile/my_ads_screen.dart';
import '../screens/profile/seller_dashboard_screen.dart';
import '../screens/profile/premium_upgrade_screen.dart';
import '../screens/profile/help_center_screen.dart';
import '../screens/profile/about_app_screen.dart';
import '../screens/profile/wallpaper_screen.dart';
import '../screens/streamer/streamer_earnings_screen.dart';
import '../screens/call/incoming_call_screen.dart';
import '../screens/call/video_call_screen.dart';
import '../screens/call/call_history_screen.dart';
import '../screens/order/my_orders_screen.dart';
import '../screens/order/order_detail_screen.dart';
import '../screens/wallet/buy_coins_screen.dart';
import '../screens/wallet/viewer_earnings_screen.dart';
import '../screens/notification/notification_screen.dart';
import '../screens/payment/payment_summary_screen.dart';
import '../screens/live/live_screen.dart';
import '../screens/live/go_live_screen.dart';
import '../screens/media/media_player_screen.dart';
import '../screens/media/playlists_screen.dart';
import '../screens/onboarding/account_selection_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_ad_revenue_screen.dart';
import '../screens/seller/earnings_dashboard.dart';
import '../screens/music/music_player_screen.dart';
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
        path: AppRoutes.feed,
        builder: (context, state) => const FeedScreen(),
      ),
      GoRoute(
        path: AppRoutes.cart,
        builder: (context, state) => const CartScreen(),
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
        path: AppRoutes.incomingCall,
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>;
          return IncomingCallScreen(
            callId: data['callId'] as String,
            callerId: data['callerId'] as String,
            callerName: data['callerName'] as String? ?? 'Unknown',
            callerImage: data['callerImage'] as String?,
            channelName: data['channelName'] as String,
            callType: data['callType'] as String? ?? 'video',
          );
        },
      ),
      GoRoute(
        path: AppRoutes.orders,
        builder: (context, state) => const MyOrdersScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.orderDetail}/:id',
        builder: (context, state) {
          return OrderDetailScreen(orderId: state.pathParameters['id']!);
        },
      ),
      GoRoute(
        path: AppRoutes.buyCoins,
        builder: (context, state) => const BuyCoinsScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.payment}/:productId',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>;
          return PaymentSummaryScreen(
            sellerId: data['sellerId'] as String,
            sellerName: data['sellerName'] as String,
            productId: state.pathParameters['productId']!,
            productName: data['productName'] as String,
            productPrice: (data['productPrice'] as num).toDouble(),
          );
        },
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
        path: '${AppRoutes.goLive}/:productId/:productName',
        builder: (context, state) {
          final productId = state.pathParameters['productId']!;
          final productName = state.pathParameters['productName']!;
          final image = state.extra as String?;
          return GoLiveScreen(
            productId: productId,
            productName: productName,
            productImage: image,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.live,
        builder: (context, state) {
          return LiveScreen(stream: state.extra as LiveStream);
        },
      ),
      GoRoute(
        path: '${AppRoutes.videoCall}/:channelName',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>?;
          return VideoCallScreen(
            channelName: state.pathParameters['channelName']!,
            isAudioOnly: data?['isAudioOnly'] as bool? ?? false,
            callId: data?['callId'] as String?,
            remoteName: data?['remoteName'] as String?,
            remoteImage: data?['remoteImage'] as String?,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.callHistory,
        builder: (context, state) => const CallHistoryScreen(),
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
        path: AppRoutes.premiumUpgrade,
        builder: (context, state) {
          final tier = state.extra as String?;
          return PremiumUpgradeScreen(initialTier: tier);
        },
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
        path: AppRoutes.wallpaper,
        builder: (context, state) => const WallpaperScreen(),
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
        path: AppRoutes.earningsDashboard,
        builder: (context, state) => const EarningsDashboard(),
      ),
      GoRoute(
        path: AppRoutes.streamerEarnings,
        builder: (context, state) => const StreamerEarningsScreen(),
      ),
      GoRoute(
        path: AppRoutes.viewerEarnings,
        builder: (context, state) => const ViewerEarningsScreen(),
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
    ],
  );
}
