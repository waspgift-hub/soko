import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../../widgets/product_cached_image.dart';
import '../../extensions/context_tr.dart';
import '../../models/transaction_model.dart';
import '../../services/api_config.dart';
import '../../services/clickpesa_service.dart';
import '../../app/routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/order_status_config.dart';
import '../chat/chat_navigation.dart';
import '../../widgets/google_loading.dart';
import '../../widgets/soko_vibe_loading.dart';
import '../../widgets/payment_banner.dart';
import '../../widgets/payment_result_dialog.dart';
import '../../widgets/buyer_transport_sheet.dart';
import '../../widgets/location_map_widget.dart';
import '../../widgets/call_seller_button.dart';
import '../../utils/phone_utils.dart';
import '../../utils/rate_limiter.dart';

class OrderDetailScreen extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;

  const OrderDetailScreen({super.key, required this.docId, required this.data});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  Timer? _countdownTimer;
  Timer? _autoRefreshTimer;
  Duration? _remaining;
  bool _isLoading = true;
  String? _releasingTxId;
  String? _disputingTxId;
  bool _showAllDetails = false;
  Map<String, dynamic> _liveData = const {};
  StreamSubscription? _orderSub;
  StreamSubscription? _txSub;
  DateTime? _lastAutoRefresh;

  // Payment state (used when status is "quoted")
  bool _paying = false;
  double _gatewayFee = 0;
  bool _gatewayFeeFetching = false;
  Timer? _gatewayFeeDebounce;
  final _phoneController = TextEditingController();
  String? _phoneError;

  // Delivery OTP state
  String _buyerOtp = '';
  StreamSubscription? _otpSub;
  final _sellerOtpController = TextEditingController();
  bool _verifyingOtp = false;
  String? _otpError;
  int _otpAttemptsRemaining = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startCountdown();
    _initRealtimeListeners();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _isLoading = false);
    });
    if (status == 'quoted') {
      _fetchGatewayFee();
    }
  }

  /// Real-time: live-stream the orders doc and the transactions doc (same ID —
  /// payment txs are created with the orderId). Every quote/payment/dispatch/
  /// release change on either doc reflects instantly on this screen.
  void _initRealtimeListeners() {
    final orderRef = FirebaseFirestore.instance.collection('orders').doc(widget.docId);
    final txRef = FirebaseFirestore.instance.collection('transactions').doc(widget.docId);

    _orderSub = orderRef.snapshots().listen((snap) {
      if (!mounted) return;
      final orderData = snap.exists ? snap.data() : null;
      final txSnap = _txData;
      setState(() => _liveData = _mergeDocs(orderData, txSnap));
      _maybeInitQuotedPayment();
      _maybeSubscribeToOtp();
    });

    _txSub = txRef.snapshots().listen((snap) {
      if (!mounted) return;
      _txData = snap.exists ? snap.data() : null;
      setState(() => _liveData = _mergeDocs(_orderData, _txData));
      _maybeInitQuotedPayment();
      _maybeSubscribeToOtp();
    });
  }

  /// Fetches the ClickPesa gateway fee when the order becomes 'quoted' while
  /// this screen is already open (e.g. the seller quotes while the buyer
  /// watches the order). Debounced + guarded so two live streams can't fire
  /// duplicate requests.
  void _maybeInitQuotedPayment() {
    if (status != 'quoted' || _gatewayFeeFetching) return;
    _gatewayFeeFetching = true;
    _gatewayFeeDebounce?.cancel();
    _gatewayFeeDebounce = Timer(const Duration(milliseconds: 400), () {
      _gatewayFeeFetching = false;
      _fetchGatewayFee();
    });
  }

  void _maybeSubscribeToOtp() {
    if (_otpSub != null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final isBuyer = d['buyerId'] == user.uid;
    if (!isBuyer || status != 'dispatched') return;
    final otpRef = FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.docId)
        .collection('delivery_otp')
        .doc('buyer');
    _otpSub = otpRef.snapshots().listen((snap) {
      if (!mounted || !snap.exists) return;
      final data = snap.data();
      setState(() => _buyerOtp = data?['otp'] as String? ?? '');
    });
  }

  Map<String, dynamic>? _orderData;
  Map<String, dynamic>? _txData;

  Map<String, dynamic> _mergeDocs(Map<String, dynamic>? order, Map<String, dynamic>? tx) {
    _orderData = order;
    final merged = {...?order};
    if (tx != null) {
      merged.addAll(tx);
      // The transactions doc is the payment source of truth once it exists;
      // its 'pending' status only means the payment prompt was sent.
      if (tx['status'] is String && tx['status'] != 'pending') {
        merged['status'] = tx['status'];
      }
    }
    return merged;
  }

  void _startCountdown() {
    final est = d['estimatedDelivery'] as Timestamp?;
    if (est != null) {
      _updateRemaining(est);
      _countdownTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateRemaining(est),
      );
    }
  }

  void _updateRemaining(Timestamp est) {
    final diff = est.toDate().difference(DateTime.now());
    if (mounted)
      setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _pulseController.stop();
    } else if (state == AppLifecycleState.resumed) {
      _pulseController.repeat(reverse: true);
      if (mounted) setState(() => _lastAutoRefresh = DateTime.now());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _countdownTimer?.cancel();
    _autoRefreshTimer?.cancel();
    _gatewayFeeDebounce?.cancel();
    _orderSub?.cancel();
    _txSub?.cancel();
    _otpSub?.cancel();
    _phoneController.dispose();
    _sellerOtpController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get d => _liveData.isNotEmpty ? _liveData : widget.data;
  String get status => d['status'] as String? ?? 'pending';

  bool get _isPaidState =>
      status == 'paid_escrow_hold' ||
      status == 'escrow_hold' ||
      status == 'dispatched' ||
      status == 'delivered' ||
      status == 'delivery_confirmed' ||
      status == 'completed';

  bool get _isCompletedState =>
      status == 'delivered' ||
      status == 'delivery_confirmed' ||
      status == 'confirmed' ||
      status == 'completed';

  String _nf(num n) => NumberFormat('#,###', 'en').format(n);

  int _currentStep() {
    switch (status) {
      case 'pending':
        return 0;
      case 'awaiting_shipping_quote':
        return 0;
      case 'quoted':
        case 'awaiting_payment':
        case 'paid':
          return 1;
        case 'paid_escrow_hold':
        case 'escrow_hold':
          return 2;
        case 'dispatched':
          return 3;
        case 'delivered':
        case 'delivery_confirmed':
        case 'confirmed':
          return 4;
        case 'completed':
          return 5;
        default:
          return 0;
    }
  }

  String _formatCountdown(Duration d) {
    if (d.isNegative || d == Duration.zero) return '\u2014';
    final days = d.inDays;
    final hours = d.inHours.remainder(24);
    final mins = d.inMinutes.remainder(60);
    if (days > 0) return '${days}d ${hours}h ${mins}m';
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  String _formatRelative(Duration d) {
    if (d.inSeconds < 10) return context.tr('just_now');
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    return '${d.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) return _buildSkeleton(context, cs);

    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(cs),
          Column(
            children: [
              _buildHeader(context, cs),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    _buildHeroSection(context, cs),
                    const SizedBox(height: 16),
                    _buildStatusBanner(context, cs),
                    const SizedBox(height: 16),
                if (_isPaidState)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: cs.successGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cs.successGreen.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: cs.successGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.shield_outlined, size: 18, color: cs.successGreen),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.tr('escrow_secure_note', 'Fedha zako ziko salama kwenye escrow hadi uthibitishe upokeaji'),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: cs.successGreen,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                    _buildTimeline(context, cs),
                    const SizedBox(height: 16),
                    _buildOrderTable(context, cs),
                    const SizedBox(height: 12),
                    if (d['deliveryAddress'] != null ||
                        d['dispatchProof'] != null ||
                        _hasFees()) ...[
                      _buildExpandableDetails(context, cs),
                      const SizedBox(height: 12),
                    ],
                    _buildActions(context, cs),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
              _buildBottomBar(context, cs),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton(BuildContext context, ColorScheme cs) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 300,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: List.generate(
                4,
                (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: GoogleLoading(size: 24, strokeWidth: 2.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cs.surface, cs.surfaceContainerLow.withValues(alpha: 0.3)],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme cs) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: cs.onSurface,
              ),
            ),
            onPressed: () => context.pop(),
          ),
          const Spacer(),
          Text(
            context.tr('order_details'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: cs.onSurface,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context, ColorScheme cs) {
    final productName = d['productName'] as String? ?? context.tr('product');
    final productImage = d['productImage'] as String? ?? '';
    final price = (d['productPrice'] ?? 0).toDouble();
    final totalAmount = (d['totalAmount'] as num?)?.toDouble() ?? price;
    final orderIdDisplay = widget.docId.length > 12
        ? '#...${widget.docId.substring(widget.docId.length - 8)}'
        : '#${widget.docId}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          productImage.isNotEmpty
              ? ProductCachedImage(
                  url: productImage,
                  height: 220,
                  fit: BoxFit.cover,
                )
              : _heroPlaceholder(cs, productName),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    orderStatusInfo(status, cs).icon,
                    size: 13,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    orderStatusInfo(status, cs).label(context),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      'TZS ${_nf(totalAmount.toInt())}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.greenAccent,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        orderIdDisplay,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroPlaceholder(ColorScheme cs, String name) {
    return Container(
      width: double.infinity,
      height: 220,
      color: cs.primary.withValues(alpha: 0.1),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 48,
              color: cs.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            Text(name, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context, ColorScheme cs) {
    final showCountdown = _remaining != null &&
        !_remaining!.isNegative &&
        _remaining!.inSeconds > 0;

    // Subtitle must reflect the real payment state, not a generic hint — a
    // failed order shows the failure reason, a confirmed one shows the amount.
    String statusSubtitle = context.tr('order_status_hint');
    if (status == 'failed') {
      final reason = d['failureReason'];
      statusSubtitle = reason is String && reason.isNotEmpty
          ? reason
          : context.tr('payment_failed_short');
    } else if (status == 'escrow_hold' ||
        status == 'paid_escrow_hold' ||
        status == 'dispatched' ||
        status == 'delivered' ||
        status == 'delivery_confirmed' ||
        status == 'completed') {
      final amt = (d['totalAmount'] is num ? d['totalAmount'] as num : 0).toDouble();
      statusSubtitle = '${context.tr('paid_label')} \u2022 TZS ${_nf(amt)}';
    } else if (status == 'quoted' || status == 'awaiting_payment') {
      statusSubtitle = context.tr('awaiting_payment');
    }

    return OrderStatusBanner(
      status: status,
      subtitle: statusSubtitle,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showCountdown)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, size: 12, color: Colors.orange),
                  const SizedBox(width: 4),
                  Text(
                    _formatCountdown(_remaining!),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          if (_lastAutoRefresh != null) ...[
            if (showCountdown) const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.autorenew, size: 10, color: cs.successGreen),
                const SizedBox(width: 3),
                  Text(
                    '${context.tr('last_updated')} ${_formatRelative(DateTime.now().difference(_lastAutoRefresh!))}',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: cs.successGreen,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, ColorScheme cs) {
    final steps = [
      _StepData(
        context.tr('step_shipping_quote'),
        Icons.local_shipping_outlined,
        Colors.orange,
      ),
      _StepData(
        context.tr('waiting_payment'),
        Icons.account_balance_wallet_outlined,
        Colors.blue,
      ),
      _StepData(
        context.tr('step_in_escrow'),
        Icons.verified_user_outlined,
        Colors.purple,
      ),
      _StepData(
        context.tr('shipped'),
        Icons.inventory_2_outlined,
        cs.successGreen,
      ),
      _StepData(
        context.tr('confirmed'),
        Icons.check_circle_outline,
        cs.successGreen,
      ),
      _StepData(
        context.tr('completed'),
        Icons.check_circle_rounded,
        cs.successGreen,
      ),
    ];
    final current = _currentStep();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.route_rounded, size: 16, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Text(
                context.tr('order_status'),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (_remaining != null &&
                  !_remaining!.isNegative &&
                  _remaining!.inSeconds > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 12,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatCountdown(_remaining!),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < steps.length; i++)
            _verticalStep(cs, steps[i], i, current, steps.length),
        ],
      ),
    );
  }

  Widget _verticalStep(
    ColorScheme cs,
    _StepData step,
    int i,
    int current,
    int total,
  ) {
    final active = i <= current;
    final isCurrent = i == current;
    final isLast = i == total - 1;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Column(
            children: [
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (context, _) {
                  return Container(
                    width: isCurrent ? 40 : 34,
                    height: isCurrent ? 40 : 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? step.color
                          : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      border: isCurrent
                          ? Border.all(
                              color: step.color.withValues(alpha: 0.5),
                              width: 3,
                            )
                          : null,
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: step.color.withValues(
                                  alpha: _pulseAnim.value * 0.4,
                                ),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ]
                          : active
                          ? [
                              BoxShadow(
                                color: step.color.withValues(alpha: 0.2),
                                blurRadius: 6,
                              ),
                            ]
                          : [],
                    ),
                    child: Icon(
                      active ? Icons.check_rounded : step.icon,
                      size: isCurrent ? 18 : 16,
                      color: active
                          ? cs.surface
                          : cs.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                  );
                },
              ),
              if (!isLast)
                Container(
                  width: 3,
                  height: 22,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: active
                        ? step.color.withValues(alpha: 0.4)
                        : cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: isLast ? 0 : 4,
              top: isCurrent ? 8 : 5,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isCurrent
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: active
                          ? cs.onSurface
                          : cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: step.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      context.tr('in_progress'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: step.color,
                      ),
                    ),
                  )
                else if (active)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: step.color.withValues(alpha: 0.7),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderTable(BuildContext context, ColorScheme cs) {
    final price = (d['productPrice'] ?? 0).toDouble();
    final shippingCost = (d['shippingCost'] as num?)?.toDouble();
    final totalAmount = (d['totalAmount'] as num?)?.toDouble() ?? price;
    final platformFee =
        (d['platformFee'] as num?)?.toDouble() ??
        (d['sokoLanguCommission'] as num?)?.toDouble() ??
        (price * 0.035);
    final processingFee = (d['processingFee'] as num?)?.toDouble() ?? getUssdPushFee(price);
    final discount = (d['discount'] as num?)?.toDouble();
    final txId =
        d['transactionId'] as String? ??
        d['mpesaTransactionId'] as String? ??
        '';
    final paymentMethod = d['paymentMethod'] as String? ?? 'ClickPesa';
    final sellerName = d['sellerName'] as String? ?? '';
    final sellerId = d['sellerId'] as String? ?? '';
    final buyerName = d['buyerName'] as String? ?? '';
    final buyerPhone = d['buyerPhone'] as String? ?? '';
    final buyerEmail = d['buyerEmail'] as String? ?? '';
    final createdAt = d['createdAt'];
    final dateStr = createdAt is Timestamp
        ? DateFormat('dd MMM yyyy HH:mm').format(createdAt.toDate())
        : '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 16,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                context.tr('order_details'),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (_isCompletedState)
                Semantics(
                  button: true,
                  label: context.tr('view_receipt'),
                  onTap: () => context.push('${AppRoutes.receipt}/${widget.docId}'),
                  child: GestureDetector(
                    excludeFromSemantics: true,
                    onTap: () =>
                        context.push('${AppRoutes.receipt}/${widget.docId}'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_outlined,
                            size: 13,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            context.tr('receipt'),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _tableRow(cs, context.tr('order_id'), widget.docId, copyable: true),
          _tableRow(cs, context.tr('date'), dateStr),
          _tableRow(
            cs,
            context.tr('seller'),
            sellerName,
            onTap: sellerId.isNotEmpty
                ? () => ChatNavigation.openSellerChat(
                    context,
                    sellerId,
                    sellerName,
                  )
                : null,
          ),
          _tableRow(cs, context.tr('buyer_label'), buyerName),
          if (buyerPhone.isNotEmpty)
            _tableRow(cs, context.tr('phone'), buyerPhone, copyable: true),
          if (buyerEmail.isNotEmpty)
            _tableRow(cs, context.tr('email'), buyerEmail, copyable: true),
          _tableRow(cs, context.tr('payment_method'), paymentMethod),
          if (txId.isNotEmpty)
            _tableRow(
              cs,
              context.tr('transaction_id_label'),
              txId,
              copyable: true,
            ),
          // The quoted payment card already shows the full price breakdown,
          // so skip it here to avoid showing the same figures twice.
          if (status != 'quoted') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 15,
                        color: cs.primary.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.tr('payment_breakdown'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _tableRow(
                    cs,
                    context.tr('product_price'),
                    'TZS ${_nf(price.toInt())}',
                  ),
                  if (shippingCost != null && shippingCost > 0)
                    _tableRow(
                      cs,
                      context.tr('shipping_cost'),
                      'TZS ${_nf(shippingCost.toInt())}',
                    ),
                  if (discount != null && discount > 0)
                    _tableRow(
                      cs,
                      context.tr('discount'),
                      '-TZS ${_nf(discount.toInt())}',
                    ),
                  _tableRow(
                    cs,
                    context.tr('soko_vibe_commission'),
                    'TZS ${_nf(platformFee.toInt())}',
                  ),
                  _tableRow(
                    cs,
                    context.tr('processing_fee'),
                    'TZS ${_nf(processingFee.toInt())}',
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          cs.primary.withValues(alpha: 0.14),
                          cs.primary.withValues(alpha: 0.06),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Text(
                          context.tr('total'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'TZS ${_nf(totalAmount.toInt())}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tableRow(
    ColorScheme cs,
    String label,
    String value, {
    bool copyable = false,
    bool bold = false,
    bool accent = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.06),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: accent ? cs.primary : cs.onSurface,
                ),
              ),
            ),
            if (copyable)
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.tr('copied_to_clipboard')),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                size: 14,
                color: cs.primary.withValues(alpha: 0.5),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandableDetails(BuildContext context, ColorScheme cs) {
    // The orders API stores the address as flat fields
    // (region/district/ward/street/landmarks); fall back to them when the
    // nested deliveryAddress map is absent.
    final address = d['deliveryAddress'] as Map<String, dynamic>?
        ?? (((d['region'] as String? ?? '').isNotEmpty ||
                (d['district'] as String? ?? '').isNotEmpty ||
                (d['street'] as String? ?? '').isNotEmpty)
            ? {
                'region': d['region'],
                'district': d['district'],
                'ward': d['ward'],
                'street': d['street'],
                'landmarks': d['landmarks'],
                'latitude': d['latitude'],
                'longitude': d['longitude'],
              }
            : null);
    final dispatch = d['dispatchProof'] as Map<String, dynamic>?;
    final hasAddress = address != null;
    final hasDispatch = dispatch != null;
    // The quoted payment card already lists the fees, so hide this duplicate
    // breakdown while the order is awaiting payment.
    final hasFees = _hasFees() && status != 'quoted';

    if (!hasAddress && !hasDispatch && !hasFees) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _showAllDetails ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: cs.primary,
            ),
          ),
          title: Text(
            context.tr('more_details'),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: cs.onSurface,
            ),
          ),
          children: [
            if (hasAddress) ...[
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 15,
                    color: cs.primary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('shipping_address'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (address['region'] != null)
                _addrRow(cs, context.tr('region'), address['region'] as String),
              if (address['district'] != null)
                _addrRow(
                  cs,
                  context.tr('district'),
                  address['district'] as String,
                ),
              if (address['ward'] != null)
                _addrRow(cs, context.tr('ward'), address['ward'] as String),
              if (address['street'] != null)
                _addrRow(cs, context.tr('street'), address['street'] as String),
              if (address['houseNumber'] != null)
                _addrRow(
                  cs,
                  context.tr('house_number'),
                  address['houseNumber'] as String,
                ),
              if (address['landmarks'] != null)
                _addrRow(
                  cs,
                  context.tr('landmarks'),
                  address['landmarks'] as String,
                ),
              if (address['latitude'] != null && address['longitude'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LocationMapWidget(
                    targetLat: (address['latitude'] as num).toDouble(),
                    targetLng: (address['longitude'] as num).toDouble(),
                    height: 160,
                    showDistance: true,
                    interactive: false,
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (hasDispatch) ...[
              Row(
                children: [
                  Icon(
                    Icons.local_shipping_outlined,
                    size: 15,
                    color: cs.primary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('shipping_details'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (dispatch['courierName'] != null)
                _addrRow(
                  cs,
                  context.tr('courier_company_name'),
                  dispatch['courierName'] as String,
                ),
              if (dispatch['trackingNumber'] != null)
                _addrRow(
                  cs,
                  context.tr('tracking_number'),
                  dispatch['trackingNumber'] as String,
                ),
              if (dispatch['driverPhone'] != null)
                _addrRow(
                  cs,
                  context.tr('driver_phone'),
                  dispatch['driverPhone'] as String,
                ),
              if (dispatch['notes'] != null)
                _addrRow(
                  cs,
                  context.tr('additional_notes'),
                  dispatch['notes'] as String,
                ),
              const SizedBox(height: 12),
            ],
            if (hasFees) ...[
              Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 15,
                    color: cs.primary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('payment_breakdown'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildFeeRows(cs),
            ],
          ],
        ),
      ),
    );
  }

  bool _hasFees() {
    final platformFee =
        (d['platformFee'] as num?)?.toDouble() ??
        (d['sokoLanguCommission'] as num?)?.toDouble() ??
        0;
    final processingFee = (d['processingFee'] as num?)?.toDouble() ?? 0;
    final sellerReceives = (d['sellerReceives'] as num?)?.toDouble() ?? 0;
    return platformFee > 0 || processingFee > 0 || sellerReceives > 0;
  }

  Widget _buildFeeRows(ColorScheme cs) {
    final platformFee =
        (d['platformFee'] as num?)?.toDouble() ??
        (d['sokoLanguCommission'] as num?)?.toDouble() ??
        0;
    final processingFee = (d['processingFee'] as num?)?.toDouble() ?? 0;
    final sellerReceives = (d['sellerReceives'] as num?)?.toDouble() ?? 0;
    final children = <Widget>[];
    if (platformFee > 0) {
      children.add(
        _addrRow(
          cs,
          context.tr('soko_vibe_commission'),
          '-TZS ${_nf(platformFee.toInt())}',
        ),
      );
    }
    if (processingFee > 0) {
      children.add(
        _addrRow(
          cs,
          context.tr('processing_fee'),
          'TZS ${_nf(processingFee.toInt())}',
        ),
      );
    }
    if (sellerReceives > 0) {
      children.add(const SizedBox(height: 4));
      children.add(
        Container(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
      );
      children.add(const SizedBox(height: 4));
      children.add(
        _addrRow(
          cs,
          context.tr('seller_receives'),
          'TZS ${_nf(sellerReceives.toInt())}',
          bold: true,
        ),
      );
    }
    return Column(children: children);
  }

  Widget _addrRow(
    ColorScheme cs,
    String label,
    String value, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, ColorScheme cs) {
    final user = FirebaseAuth.instance.currentUser;
    final isBuyer = user != null && d['buyerId'] == user.uid;
    final isSeller = user != null && d['sellerId'] == user.uid;
    final canConfirm = status == 'delivered' || status == 'dispatched';
    final canFillTransport =
        (status == 'escrow_hold' || status == 'paid_escrow_held') &&
        isBuyer &&
        d['buyerTransport'] == null;
    final canDispute =
        status == 'paid_escrow_hold' ||
        status == 'escrow_hold' ||
        status == 'dispatched' ||
        status == 'delivered';
    final canCancel = status == 'paid_escrow_hold' || status == 'escrow_hold';

    if ((status == 'pending' || status == 'awaiting_shipping_quote') && isBuyer) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.hourglass_top, color: cs.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.tr('order_submitted_to_seller', 'Agizo limewasilishwa kwa muuzaji. Subiri muuzaji kutoa gharama ya usafirishaji.'),
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    if (status == 'quoted' && isBuyer) {
      final shipping = _quotedShippingCost;
      final price = _quotedProductPrice;
      final platformFee = _quotedPlatformFee;
      final total = _quotedTotal;

      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.payments_outlined, color: cs.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Text(context.tr('payment_title', 'Malipo'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                children: [
                  _feeRow2(cs, context.tr('product_price'), 'TZS ${_nf(price.toInt())}', cs.onSurface),
                  if (shipping > 0) ...[
                    const SizedBox(height: 6),
                    _feeRow2(cs, context.tr('shipping_cost'), 'TZS ${_nf(shipping.toInt())}', cs.tertiary),
                  ],
                  const SizedBox(height: 6),
                  _feeRow2(cs, context.tr('commission_3_5', 'Commission (3.5%)'), 'TZS ${_nf(platformFee.toInt())}', cs.onSurfaceVariant),
                  if (_gatewayFee > 0) ...[
                    const SizedBox(height: 6),
                    _feeRow2(cs, context.tr('gateway_fee'), 'TZS ${_nf(_gatewayFee.toInt())}', cs.secondary),
                  ],
                  const SizedBox(height: 8),
                  Container(height: 1, color: cs.outlineVariant.withValues(alpha: 0.2)),
                  const SizedBox(height: 8),
                  _feeRow2(cs, context.tr('total'), 'TZS ${_nf(total.toInt())}', cs.primary, bold: true),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text(
              context.tr('phone_field_hint', 'Nambari ya simu'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: cs.onSurface),
              decoration: InputDecoration(
                hintText: '07XX XXX XXX',
                hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                prefixIcon: Icon(Icons.phone_android, color: cs.onSurface.withValues(alpha: 0.59)),
                errorText: _phoneError,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: cs.primary, width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: cs.error, width: 1),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _paying ? null : _payQuotedOrder,
                icon: _paying
                    ? SokoVibeThreeDotLoader(size: 20, dotSize: 5, color: cs.surface)
                    : const Icon(Icons.payment, size: 20),
                label: Text(
                  _paying ? context.tr('processing_label') : context.tr('pay_amount_tzs').replaceAll('{0}', _nf(total)),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!canConfirm && !canDispute && !canCancel && !canFillTransport)
      return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          if (canFillTransport)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _submitTransport(),
                icon: const Icon(Icons.local_shipping_outlined, size: 20),
                label: Text(context.tr('transport_details')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          if (canConfirm && status == 'dispatched' && isBuyer)
            _buildBuyerOtpCard(cs),
          if (canConfirm && status == 'dispatched' && isSeller)
            _buildSellerOtpForm(cs),
          if (canConfirm && status != 'dispatched')
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _releasingTxId == widget.docId
                    ? null
                    : () => _confirmDelivery(widget.docId),
                icon: _releasingTxId == widget.docId
                    ? const GoogleLoading(size: 20, strokeWidth: 2)
                    : const Icon(Icons.verified, size: 20),
                label: Text(
                  _releasingTxId == widget.docId
                      ? context.tr('confirming_label')
                      : context.tr('confirm_receipt'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.successGreen,
                  foregroundColor: cs.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          if (canDispute || canCancel) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (canDispute)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _disputingTxId == widget.docId
                          ? null
                          : () => _raiseDispute(widget.docId),
                      icon: _disputingTxId == widget.docId
                          ? const GoogleLoading(size: 16, strokeWidth: 2)
                          : const Icon(Icons.gavel, size: 16),
                      label: Text(context.tr('dispute_button')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                        side: BorderSide(
                          color: cs.error.withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                if (canDispute && canCancel) const SizedBox(width: 10),
                if (canCancel)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _cancelOrder(widget.docId),
                      icon: const Icon(Icons.money_off, size: 16),
                      label: Text(context.tr('cancel')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                        side: BorderSide(
                          color: cs.error.withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _feeRow2(ColorScheme cs, String label, String value, Color valueColor, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant, fontWeight: bold ? FontWeight.w600 : FontWeight.w400)),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: valueColor)),
      ],
    );
  }

  Widget _buildBuyerOtpCard(ColorScheme cs) {
    final otp = _buyerOtp;
    final productName = d['productName'] as String? ?? 'Bidhaa';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.error.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: cs.error, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('otp_security_warning', 'USIJIGAWANIE NAMBARI HII MPAKA UPOKEE NA KUKAGUA BIDHAA YAKO.'),
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.error, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.tr('delivery_otp_label', 'Nambari ya Uthibitisho'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (otp.isNotEmpty)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: otp));
                HapticFeedback.mediumImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('otp_copied', 'OTP imek Copies')), behavior: SnackBarBehavior.floating),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                ),
                child: Text(
                  otp,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 12, color: cs.primary),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                context.tr('otp_waiting', 'Subiri muuzaji atume nambari...'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            context.tr('share_otp_with_seller', 'Mpa nambari hii muuzaji ili athibitishe utoaji'),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildSellerOtpForm(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.pin_outlined, color: cs.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr('enter_buyer_otp', 'Weka nambari ya uthibitisho kutoka kwa mnunuzi'),
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _sellerOtpController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 8, color: cs.onSurface),
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: '0000',
              hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.4), letterSpacing: 8),
              counterText: '',
              errorText: _otpError,
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: cs.error, width: 1),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('otp_attempts_remaining', 'Majaribio yaliyobaki: {0}').replaceAll('{0}', '$_otpAttemptsRemaining'),
            style: TextStyle(fontSize: 12, color: _otpAttemptsRemaining <= 1 ? cs.error : cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _verifyingOtp || _sellerOtpController.text.length != 4
                  ? null
                  : _verifyDeliveryOtp,
              icon: _verifyingOtp
                  ? const GoogleLoading(size: 20, strokeWidth: 2)
                  : const Icon(Icons.verified, size: 20),
              label: Text(
                _verifyingOtp
                    ? context.tr('verifying_label')
                    : context.tr('verify_and_release'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.successGreen,
                foregroundColor: cs.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyDeliveryOtp() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final otp = _sellerOtpController.text.trim();
    if (otp.length != 4) return;
    setState(() { _verifyingOtp = true; _otpError = null; });
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/orders/verify-delivery'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await user.getIdToken()}',
        },
        body: jsonEncode({'orderId': widget.docId, 'otp': otp}),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200 && result['success'] == true) {
        if (mounted) {
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('otp_verified_success')), behavior: SnackBarBehavior.floating),
          );
          _sellerOtpController.clear();
        }
      } else {
        if (mounted) {
          final error = result['error'] ?? context.tr('otp_verification_failed');
          final remaining = result['attemptsRemaining'] as int?;
          setState(() {
            _otpError = error;
            if (remaining != null) _otpAttemptsRemaining = remaining;
          });
          HapticFeedback.heavyImpact();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _otpError = context.tr('network_error'));
    }
    if (mounted) setState(() => _verifyingOtp = false);
  }

  Widget _buildBottomBar(BuildContext context, ColorScheme cs) {
    final sellerId = d['sellerId'] as String? ?? '';
    final sellerName = d['sellerName'] as String? ?? '';
    final showTracking = status == 'dispatched';
    final showReceipt = _isCompletedState;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.92),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            CallSellerButton(
              phone: d['sellerPhone'] as String? ?? '',
              iconOnly: true,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.whatsappGreen,
                    foregroundColor: cs.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.chat_outlined, size: 17),
                  onPressed: sellerId.isNotEmpty
                      ? () => ChatNavigation.openSellerChat(
                          context,
                          sellerId,
                          sellerName,
                        )
                      : null,
                  label: Text(
                    context.tr('contact_seller'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
            if (showTracking) ...[
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.primary,
                      side: BorderSide(
                        color: cs.primary.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.track_changes_outlined, size: 17),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.tr('feature_coming_soon')),
                        behavior: SnackBarBehavior.floating,
                      ),
                    ),
                    label: Text(
                      context.tr('track'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
            if (showReceipt) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.primary,
                    side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.receipt_outlined, size: 17),
                  onPressed: () =>
                      context.push('${AppRoutes.receipt}/${widget.docId}'),
                  label: Text(
                    context.tr('receipt'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelivery(String txId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _releasingTxId = txId);
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/release'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await user.getIdToken()}',
        },
        body: jsonEncode({'orderId': txId, 'userId': user.uid}),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200 && result['success'] == true) {
        if (mounted) {
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('delivery_confirmed_msg')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['error'] ?? context.tr('confirm_failed_msg'),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr('confirm_failed_msg')}: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    if (mounted) setState(() => _releasingTxId = null);
  }

  Future<void> _submitTransport() async {
    final saved = await showBuyerTransportSheet(
      context: context,
      orderId: widget.docId,
    );
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('transport_saved')),
        behavior: SnackBarBehavior.floating,
      ),
    );
    setState(() {});
  }

  Future<void> _raiseDispute(String txId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('dispute_title')),
        content: Text(context.tr('dispute_notify_admin')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('open')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _disputingTxId = txId);
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/dispute'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await user.getIdToken()}',
        },
        body: jsonEncode({'orderId': txId, 'userId': user.uid}),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200 && result['success'] == true) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('dispute_opened_msg')),
              behavior: SnackBarBehavior.floating,
            ),
          );
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? context.tr('dispute_failed')),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.trError(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    if (mounted) setState(() => _disputingTxId = null);
  }

  Future<void> _cancelOrder(String txId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('cancel_order_title')),
        content: Text(context.tr('cancel_order_refund_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(context.tr('yes_cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/escrow/cancel'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await user.getIdToken()}',
        },
        body: jsonEncode({'orderId': txId, 'userId': user.uid}),
      );
      final result = jsonDecode(resp.body);
      if (resp.statusCode == 200 && result['success'] == true) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('order_cancelled_refunded')),
              behavior: SnackBarBehavior.floating,
            ),
          );
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['error'] ?? context.tr('cancel_order_failed'),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.trError(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  // ─── Payment helpers for quoted state ───

  Future<void> _fetchGatewayFee() async {
    try {
      final price = (d['productPrice'] ?? 0).toDouble();
      final resp = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/gateway-fee'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'method': 'ussd_push', 'amount': price.round()}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (mounted) setState(() => _gatewayFee = (data['fee'] as num).toDouble());
      }
    } catch (_) {}
  }

  double get _quotedShippingCost =>
      (d['shippingCost'] as num?)?.toDouble() ?? 0;
  double get _quotedProductPrice =>
      (d['productPrice'] ?? 0).toDouble();
  double get _quotedPlatformFee => _quotedProductPrice * 0.035;
  double get _quotedTotal =>
      _quotedProductPrice + _quotedShippingCost + _quotedPlatformFee + _gatewayFee;

  Future<void> _payQuotedOrder() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!await RateLimiter.canProceed(action: 'pay_order', cooldown: const Duration(seconds: 10))) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait before trying again')),
      );
      return;
    }

    final raw = _phoneController.text.trim();
    if (raw.isEmpty) {
      setState(() => _phoneError = context.tr('phone_validator_empty'));
      return;
    }
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) {
      setState(() => _phoneError = context.tr('phone_validator_invalid'));
      return;
    }
    setState(() { _phoneError = null; _paying = true; });
    try {
      final normalizedPhone = PhoneUtils.toE164(raw);

      final result = await ClickPesaService.initiateMarketplacePayment(
        productPrice: _quotedProductPrice,
        productName: d['productName'] ?? '',
        productId: d['productId'] ?? '',
        sellerId: d['sellerId'] ?? '',
        sellerName: d['sellerName'] ?? '',
        email: user.email ?? '',
        phone: normalizedPhone,
        buyerId: user.uid,
        buyerName: user.displayName ?? '',
        deliveryType: (d['deliveryType'] as String?) ?? 'local',
        paymentMethod: 'ussd_push',
        existingTransactionId: widget.docId,
        shippingCost: _quotedShippingCost,
      );

      if (result == null || result['order_id'] == null) {
        final errMsg = result?['error'] as String? ?? context.tr('payment_initiation_failed');
        if (mounted) _showError(errMsg);
        setState(() => _paying = false);
        return;
      }

      await RateLimiter.record('pay_order');
      if (mounted) {
        setState(() => _paying = false);
        RealtimePaymentBanner.show(
          context: context,
          orderId: result['order_id'] as String? ?? '',
          successStatuses: ['escrow_hold', 'paid_escrow_held'],
          processingTitle: context.tr('processing_payment'),
          processingSubtitle: context.tr('check_phone_enter_pin'),
          successTitle: context.tr('payment_successful'),
          failedTitle: context.tr('payment_failed'),
          successSubtitle: '${context.tr('paid_label')} \u2022 TZS ${_nf(_quotedTotal)}',
          onSuccess: () {
            if (mounted) {
              PaymentBanner.show(
                context: context,
                type: PaymentBannerType.success,
                title: context.tr('payment_successful'),
                amount: 'TZS ${_nf(_quotedTotal)}',
              );
            }
          },
          onError: (msg) {
            if (mounted) PaymentResult.show(context: context, success: false, errorMessage: msg);
          },
        );
      }
    } catch (e) {
      if (mounted) _showError(context.trError(e));
      setState(() => _paying = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error, behavior: SnackBarBehavior.floating),
    );
  }
}

class _StepData {
  final String label;
  final IconData icon;
  final Color color;
  const _StepData(this.label, this.icon, this.color);
}
