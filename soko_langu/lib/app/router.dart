import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_transitions.dart';
import '../services/ads/ad_manager.dart';
import '../services/ads/ad_route_observer.dart';
import '../models/product_model.dart';
import '../screens/auth/auth_gate.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/forgot_password_screen.dart';

import '../screens/home/product_detail.dart';
import '../screens/home/product_reviews_screen.dart';
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
import '../screens/onboarding/artwork_pack_screen.dart';
import '../screens/profile/edit_profile_screen.dart';

import '../screens/profile/wishlist_screen.dart';
import '../screens/music/music_screen.dart';
import '../screens/music/now_playing_screen.dart';
import '../screens/profile/my_ads_screen.dart';
import '../screens/profile/seller_dashboard_screen.dart';
import '../screens/profile/help_center_screen.dart';
import '../screens/profile/about_app_screen.dart';
import '../screens/profile/order_flow_screen.dart';
import '../screens/notification/notification_screen.dart';
import '../screens/notification/notification_preferences_screen.dart';
import '../screens/onboarding/account_selection_screen.dart';
import '../screens/auth/verify_email_screen.dart';

import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_user_detail_screen.dart';
import '../screens/admin/admin_kyc_screen.dart';
import '../screens/admin/admin_ads_config_screen.dart';
import '../screens/admin/admin_broadcast_screen.dart';
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
import '../screens/requests/buyer_requests_screen.dart';
import '../screens/requests/post_buyer_request_screen.dart';
import '../screens/report/admin_reports_screen.dart';
import '../screens/ai/ai_assistant_screen.dart';
import '../screens/seller/seller_analytics_screen.dart';
import '../screens/boost/boost_product_screen.dart';

import '../screens/legal/privacy_policy_screen.dart';
import '../screens/legal/terms_of_service_screen.dart';
import '../extensions/context_tr.dart';
import 'routes.dart';
import 'app_state.dart' as app_state;
import '../repositories/product_repository.dart'; // Added for V3 API loading
import '../screens/search/user_search_screen.dart';
import '../data/marketplace_taxonomy.dart';
import '../models/category_model.dart';
import '../services/category_service.dart';
import '../services/username_service.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Page<T> _premiumPage<T>(Widget child) {
  return buildAppPage<T>(child);
}

final List<String> _authRequiredRoutes = [
  AppRoutes.checkout,
  AppRoutes.kyc,
  AppRoutes.addProduct,
  AppRoutes.profile,
  AppRoutes.settings,
  AppRoutes.editProfile,
  AppRoutes.wishlist,
  AppRoutes.myAds,
  AppRoutes.sellerDashboard,
  AppRoutes.sellerEarnings,
  AppRoutes.sellerDispatch,
  AppRoutes.sellerQuote,
  AppRoutes.sellerOrders,
  AppRoutes.myPurchases,
  AppRoutes.notifications,
  AppRoutes.chats,
  AppRoutes.chat,
  AppRoutes.createGroup,
  AppRoutes.groupChat,
  AppRoutes.createFlashSale,
  AppRoutes.receipt,
  AppRoutes.orderDetail,
  AppRoutes.order, // web alias /order/:id
  AppRoutes.otp, // web alias /otp/:id
  AppRoutes.report,
  AppRoutes.buyerRequests,
  AppRoutes.postBuyerRequest,
  AppRoutes.boostProduct,
];

final List<String> _adminOnlyRoutes = [
  AppRoutes.admin,
  AppRoutes.adminUserDetail,
  AppRoutes.adminReports,
  AppRoutes.adminKyc,
  AppRoutes.adminAdsConfig,
  AppRoutes.adminBroadcast,
];


/// Reads key:value pairs (attributes preset) from a query param.
Map<String, Set<String>>? _queryAttrMap(GoRouterState state) {
  final raw = state.uri.queryParameters['attrs'];
  if (raw == null || raw.isEmpty) return null;
  final out = <String, Set<String>>{};
  for (final part in raw.split(',')) {
    final i = part.indexOf(':');
    if (i <= 0) continue;
    final key = part.substring(0, i).trim();
    final value = part.substring(i + 1).trim();
    if (key.isEmpty || value.isEmpty) continue;
    out.putIfAbsent(key, () => <String>{}).add(value);
  }
  return out.isEmpty ? null : out;
}

/// Reads a comma-separated multi-value query param for pre-selection.
Set<String>? _queryBrandSet(GoRouterState state, String key) {
  final raw = state.uri.queryParameters[key];
  if (raw == null || raw.isEmpty) return null;
  final out = raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet();
  return out.isEmpty ? null : out;
}

/// Resolves a category from a `:name` path segment using only data compiled
/// into the app, so a deep link renders on the first frame without a network
/// round trip.
///
/// Tries the stable id first, then the taxonomy's name/nameSw/aliases and every
/// subcategory name/alias. That covers old shared URLs (which used display
/// names) as well as id-based ones.
Category? _resolveCategorySync(String raw) {
  final decoded = Uri.decodeComponent(raw).trim();
  if (decoded.isEmpty) return null;
  final slug = decoded.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  return CategoryService.byId(decoded) ??
      CategoryService.byId(slug) ??
      _categoryFromTaxonomy(resolveTaxonomyByName(decoded));
}

Category? _categoryFromTaxonomy(TaxonomyCategory? tax) =>
    tax == null ? null : categoryFromTaxonomy(tax);

GoRouter buildRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.home,
    refreshListenable: app_state.appStateNotifier,
    // Publishes the on-top route to AdManager so critical flows (checkout,
    // payment, OTP, KYC, disputes) can suppress every ad centrally.
    observers: [AdRouteObserver(adManager)],
    redirect: (context, state) {
      if (!app_state.appStateNotifier.appInitialized) return null;

      final location = state.uri.toString();
      final isAuth = app_state.appStateNotifier.isAuthenticated;
      final isAdmin = app_state.appStateNotifier.isAdmin;

      final authScreens = [AppRoutes.login, AppRoutes.register];
      if (isAuth && authScreens.any((r) => location == r || location.startsWith('$r/'))) {
        return AppRoutes.home;
      }

      if (_adminOnlyRoutes.any((r) => location == r || location.startsWith('$r/'))) {
        if (!isAuth) return AppRoutes.login;
        if (!isAdmin) return AppRoutes.home;
      }

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
        pageBuilder: (context, state) {
          final extra = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : <String, dynamic>{};
          return _premiumPage(RegisterScreen(
            initialPhone: extra['phone'] as String?,
            displayPhone: extra['displayPhone'] as String?,
            otpVerified: extra['otpVerified'] == true,
          ));
        },
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        pageBuilder: (context, state) => _premiumPage(const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        pageBuilder: (context, state) {
          final extra = state.extra;
          final email = extra is Map<String, dynamic>
              ? extra['email'] as String?
              : extra is String
                  ? extra
                  : null;
          return _premiumPage(VerifyEmailScreen(email: email));
        },
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
          final extra = state.extra;
          return _premiumPage(
            extra is Product
                ? ProductDetailPage(product: extra)
                : _ProductDetailLoader(productId: state.pathParameters['id'] ?? ''),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.productReviews,
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? const {};
          final productId = extra['productId'] as String? ?? '';
          if (productId.isEmpty) return _premiumPage(const _MissingRouteData());
          return _premiumPage(ProductReviewsScreen(
            productId: productId,
            productName: extra['productName'] as String? ?? '',
          ));
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
        path: AppRoutes.notificationPreferences,
        pageBuilder: (context, state) => _premiumPage(const NotificationPreferencesScreen()),
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
        path: AppRoutes.artworkPack,
        pageBuilder: (context, state) =>
            _premiumPage(const ArtworkPackScreen(allowDismiss: true)),
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
          // In-app navigation carries the Category in `extra`. A cold deep
          // link, an App Link, and the SEO/web fallback all arrive with no
          // `extra` at all, so it is reconstructed from the stable taxonomy
          // before the screen is built — the previous code cast a null
          // `extra` into a non-nullable `Category` and threw at page build.
          final extra = state.extra;
          final resolved = extra is Category ? extra : _resolveCategorySync(
            state.pathParameters['name'] ?? '',
          );

          if (resolved != null) {
            return _premiumPage(
              CategoryProductsScreen(
                category: resolved,
                initialSubcategory: state.uri.queryParameters['sub'],
                initialBrands: _queryBrandSet(state, 'brands'),
                initialAttributes: _queryAttrMap(state),
                initialFlags: _queryBrandSet(state, 'flags'),
              ),
            );
          }

          // Unknown name and no live tree to fall back on yet: resolve
          // asynchronously through the API/Firestore layer rather than
          // rendering a permanently broken page.
          return _premiumPage(
            _CategoryProductsLoader(
              name: state.pathParameters['name'] ?? '',
              initialSubcategory: state.uri.queryParameters['sub'],
              initialBrands: _queryBrandSet(state, 'brands'),
              initialAttributes: _queryAttrMap(state),
              initialFlags: _queryBrandSet(state, 'flags'),
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.editProfile,
        pageBuilder: (context, state) => _premiumPage(const EditProfileScreen()),
      ),

      GoRoute(
        path: AppRoutes.wishlist,
        pageBuilder: (context, state) => _premiumPage(const WishlistScreen()),
      ),
      GoRoute(
        path: AppRoutes.music,
        pageBuilder: (context, state) => _premiumPage(const MusicScreen()),
        routes: [
          GoRoute(
            path: 'now-playing',
            pageBuilder: (context, state) =>
                _premiumPage(const NowPlayingScreen()),
          ),
        ],
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
        path: AppRoutes.addProduct,
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is Map<String, dynamic> && extra.containsKey('sharedMedia')) {
            final media = extra['sharedMedia'];
            final paths = media is List ? media.map((e) => e.toString()).toList() : <String>[];
            final product = extra['product'];
            return _premiumPage(AddProductScreen(
              product: product is Product ? product : null,
              initialMediaPaths: paths,
            ));
          }
          // legacy: extra is Product directly or map with product key
          if (extra is Map && extra['product'] is Product) {
            return _premiumPage(AddProductScreen(product: extra['product'] as Product));
          }
          return _premiumPage(AddProductScreen(product: extra is Product ? extra : null));
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
        path: AppRoutes.adminKyc,
        pageBuilder: (context, state) => _premiumPage(const AdminKycScreen()),
      ),
      GoRoute(
        path: AppRoutes.adminAdsConfig,
        pageBuilder: (context, state) =>
            _premiumPage(const AdminAdsConfigScreen()),
      ),
      GoRoute(
        path: AppRoutes.adminBroadcast,
        pageBuilder: (context, state) => _premiumPage(const AdminBroadcastScreen()),
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
        pageBuilder: (context, state) {
          final extra = state.extra;
          Product? product;
          var quantity = 1;
          String? variantId;
          double? unitPrice;
          if (extra is Product) {
            product = extra;
          } else if (extra is Map) {
            final p = extra['product'];
            if (p is Product) {
              product = p;
              final q = extra['quantity'];
              if (q is int && q > 0) quantity = q;
              final v = extra['variantId'];
              if (v is String) variantId = v;
              final u = extra['unitPrice'];
              if (u is num) unitPrice = u.toDouble();
            }
          }
          if (product == null) {
            return _premiumPage(const _MissingRouteData());
          }
          return _premiumPage(CheckoutScreen(
            product: product,
            quantity: quantity,
            variantId: variantId,
            unitPrice: unitPrice,
          ));
        },
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
          final data = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : <String, dynamic>{};
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
        path: AppRoutes.kyc,
        pageBuilder: (context, state) => _premiumPage(const KycScreen()),
      ),
      GoRoute(
        path: AppRoutes.report,
        pageBuilder: (context, state) {
          final extra = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : <String, dynamic>{};
          return _premiumPage(ReportScreen(
            reportedUserId: extra['reportedUserId'] as String? ?? '',
            reportedUserName: extra['reportedUserName'] as String? ?? '',
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
        path: AppRoutes.buyerRequests,
        pageBuilder: (context, state) => _premiumPage(const BuyerRequestsScreen()),
      ),
      GoRoute(
        path: AppRoutes.postBuyerRequest,
        pageBuilder: (context, state) => _premiumPage(const PostBuyerRequestScreen()),
      ),
      GoRoute(
        path: AppRoutes.boostProduct,
        pageBuilder: (context, state) {
          final extra = state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : const {};
          return _premiumPage(BoostProductScreen(
            productId: extra['productId'] as String? ?? '',
            product: extra['product'] as dynamic,
          ));
        },
      ),
      GoRoute(
        path: AppRoutes.privacyPolicy,
        pageBuilder: (context, state) => _premiumPage(const PrivacyPolicyScreen()),
      ),
      GoRoute(
        path: AppRoutes.termsOfService,
        pageBuilder: (context, state) => _premiumPage(const TermsOfServiceScreen()),
      ),
      GoRoute(
        path: AppRoutes.userSearch,
        pageBuilder: (context, state) => _premiumPage(const UserSearchScreen()),
      ),
      // Web deep-link aliases
      GoRoute(
        path: '${AppRoutes.order}/:orderId',
        redirect: (context, state) {
          final id = state.pathParameters['orderId'] ?? '';
          return '${AppRoutes.orderDetail}/$id';
        },
      ),
      GoRoute(
        path: '${AppRoutes.otp}/:orderId',
        redirect: (context, state) {
          final id = state.pathParameters['orderId'] ?? '';
          // OTP link never carries code — just order context
          return '${AppRoutes.orderDetail}/$id';
        },
      ),
      GoRoute(
        path: '/seller/:userId',
        pageBuilder: (context, state) {
          final raw = state.pathParameters['userId']!;
          return _premiumPage(_UsernameAwareProfile(raw: raw));
        },
      ),
      GoRoute(
        path: '${AppRoutes.userProfileAlias}/:userId',
        pageBuilder: (context, state) {
          final raw = state.pathParameters['userId']!;
          return _premiumPage(_UsernameAwareProfile(raw: raw));
        },
      ),
      GoRoute(
        path: '/category/:name',
        redirect: (context, state) {
          final name = state.pathParameters['name'] ?? '';
          final qs = state.uri.query;
          return '${AppRoutes.categoryProducts}/'
              '${Uri.encodeComponent(name)}$qs';
        },
      ),
    ],
  );
}

class _UsernameAwareProfile extends StatefulWidget {
  final String raw;
  const _UsernameAwareProfile({required this.raw});
  @override
  State<_UsernameAwareProfile> createState() => _UsernameAwareProfileState();
}

class _UsernameAwareProfileState extends State<_UsernameAwareProfile> {
  late final Future<String?> _uidFuture =
      UsernameService.instance.resolveToUid(widget.raw);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _uidFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final uid = snap.data ?? widget.raw;
        return PublicProfileScreen(userId: uid, userName: widget.raw);
      },
    );
  }
}

class _MissingRouteData extends StatelessWidget {
  const _MissingRouteData();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Guarded route opened without product: explain + offer recovery.
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shopping_bag_outlined, size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                context.tr('loading_error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('missing_product_hint', 'Bidhaa haikupatikana. Rudi dukani kuchagua tena.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => context.go(AppRoutes.home),
                  icon: const Icon(Icons.storefront_outlined),
                  label: Text(context.tr('back_to_shop', 'Rudi dukani')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fallback loader for a `/category-products/:name` deep link whose name is
/// not in the compiled-in taxonomy — a category the API added after this build
/// shipped. Resolves through the live category tree, then shows the standard
/// recovery screen when even that has no match.
class _CategoryProductsLoader extends StatefulWidget {
  const _CategoryProductsLoader({
    required this.name,
    this.initialSubcategory,
    this.initialBrands,
    this.initialAttributes,
    this.initialFlags,
  });

  final String name;
  final String? initialSubcategory;
  final Set<String>? initialBrands;
  final Map<String, Set<String>>? initialAttributes;
  final Set<String>? initialFlags;

  @override
  State<_CategoryProductsLoader> createState() => _CategoryProductsLoaderState();
}

class _CategoryProductsLoaderState extends State<_CategoryProductsLoader> {
  late final Future<Category?> _future = _load();

  Future<Category?> _load() async {
    final decoded = Uri.decodeComponent(widget.name).trim();
    try {
      // A live tree may know this category even when the shipped taxonomy
      // does not; `_resolveCategorySync` already covered the compiled-in case.
      final cached = CategoryService().cached;
      final hit = cached.where(
        (c) =>
            c.id == decoded ||
            c.name.toLowerCase() == decoded.toLowerCase() ||
            c.nameSw.toLowerCase() == decoded.toLowerCase(),
      );
      if (hit.isNotEmpty) return hit.first;
      return await CategoryService().getCategoryById(decoded);
    } catch (e) {
      debugPrint('DeepLink Category Load Error: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Category?>(
      future: _future,
      builder: (context, snapshot) {
        final category = snapshot.data;
        if (category != null) {
          return CategoryProductsScreen(
            category: category,
            initialSubcategory: widget.initialSubcategory,
            initialBrands: widget.initialBrands,
            initialAttributes: widget.initialAttributes,
            initialFlags: widget.initialFlags,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return const _MissingCategoryData();
      },
    );
  }
}

/// Recovery screen for a category route that resolved to nothing. Mirrors
/// `_MissingRouteData` with category-specific copy instead of a product hint.
class _MissingCategoryData extends StatelessWidget {
  const _MissingCategoryData();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.category_outlined,
                size: 48,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('loading_error'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'missing_category_hint',
                  '-category haikupatikana. Rudi dukani kuchagua tena.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => context.go(AppRoutes.category),
                  icon: const Icon(Icons.grid_view_rounded),
                  label: Text(context.tr('all_categories')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductDetailLoader extends StatefulWidget {
  const _ProductDetailLoader({required this.productId});

  final String productId;

  @override
  State<_ProductDetailLoader> createState() => _ProductDetailLoaderState();
}

class _ProductDetailLoaderState extends State<_ProductDetailLoader> {
  late final Future<Product?> _future = _load();

  Future<Product?> _load() async {
    try {
      // V3 Alignment: Use ProductRepository (API) instead of direct Firestore
      // call — authoritative price and stock come from Postgres via the API.
      final result = await ProductRepository().getProduct(widget.productId);
      return result.data;
    } catch (e) {
      debugPrint('DeepLink Product Load Error: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Product?>(
      future: _future,
      builder: (context, snapshot) {
        final product = snapshot.data;
        if (product != null) return ProductDetailPage(product: product);
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return const _MissingRouteData();
      },
    );
  }
}
