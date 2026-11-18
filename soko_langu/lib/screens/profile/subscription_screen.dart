import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../extensions/context_tr.dart';
import '../../services/subscription_service.dart';

/// Subscription & Billing: current plan, AI allowance, plan comparison, paid
/// upgrade through AzamPay, cancellation/resume, and payment history.
///
/// Every price, quota and state comes from the server (`plans.js`,
/// `ai_subscriptions`, `ai_usage`, `billing_payments`). The screen never sends
/// an amount and never decides whether a plan is active.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final SubscriptionService _service = SubscriptionService();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  UserSubscription? _current;
  List<SubscriptionPlan> _plans = const [];
  Map<String, dynamic>? _entitlements;
  AiQuota? _quota;
  List<SubscriptionInvoice> _invoices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sub = await _service.fetchSubscription();
      final plans = await _service.fetchPlans();
      final entitlements = await _service.fetchEntitlements();
      final quota = await _service.fetchAiQuota();
      final invoices = await _service.fetchInvoices();
      if (!mounted) return;
      setState(() {
        _current = sub;
        _plans = plans;
        _entitlements = entitlements;
        _quota = quota;
        _invoices = invoices;
        _loading = false;
      });
    } on SubscriptionException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  SubscriptionPlan? _planById(String? id) {
    if (id == null) return null;
    for (final p in _plans) {
      if (p.id == id) return p;
    }
    return null;
  }

  SubscriptionPlan? get _currentPlan => _planById(_current?.planId);

  bool get _canTrial {
    final status = _current?.status;
    return status == null ||
        status == 'inactive' ||
        status == 'expired' ||
        status == 'payment_failed';
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (success != null) _toast(success);
      await _load();
    } on SubscriptionException catch (e) {
      if (!mounted) return;
      _toast(e.message, error: true);
    } catch (e) {
      if (!mounted) return;
      _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message, {bool error = false}) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? cs.errorContainer : null,
      ),
    );
  }

  Future<void> _cancel() async {
    final end = _current?.effectiveEnd;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel subscription?'),
        content: Text(
          'Your plan stays active until ${_formatDate(end)}. '
          'After that you move to the free plan and lose paid features. '
          'Payments already made are not refunded. You can resume any time '
          'before the period ends.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep plan'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel plan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () async {
        final until = await _service.cancel();
        if (mounted) {
          _toast('Cancelled. Access continues until ${_formatDate(until)}.');
        }
      },
    );
  }

  Future<void> _resume() => _run(
        _service.resume,
        success: 'Subscription resumed. You will renew as usual.',
      );

  Future<void> _downgrade(SubscriptionPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Switch to ${plan.name}?'),
        content: Text(
          'The change takes effect at the end of your current billing period '
          '( ${_formatDate(_current?.currentPeriodEnd)} ). Until then you keep '
          'the features you paid for.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Schedule change'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () async {
        final at = await _service.downgrade(plan.id);
        if (mounted) {
          _toast('Switches to ${plan.name} on ${_formatDate(at)}.');
        }
      },
    );
  }

  Future<void> _openUpgradeSheet(SubscriptionPlan plan) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _UpgradeSheet(
        service: _service,
        plan: plan,
        allowTrial: _canTrial,
      ),
    );
    if (message == null || message.isEmpty || !mounted) return;
    _toast(message);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('subscription_billing', 'Subscription & Billing')),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading && _plans.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (_busy) ...[
                    const LinearProgressIndicator(minHeight: 2),
                    const SizedBox(height: 8),
                  ],
                  if (_error != null) ...[
                    _ErrorBanner(message: _error!, onRetry: _load),
                    const SizedBox(height: 12),
                  ],
                  _CurrentPlanCard(
                    subscription: _current,
                    plan: _currentPlan,
                    entitlements: _entitlements,
                    onCancel: _current?.isUsable == true && !_current!.isCancelling
                        ? _cancel
                        : null,
                    onResume: _current?.isCancelling == true ? _resume : null,
                  ),
                  if (_quota != null) ...[
                    const SizedBox(height: 12),
                    _AiUsageCard(
                      quota: _quota!,
                      showUpgrade: _quota!.ratio >= 0.8,
                      onUpgrade: _plans.isEmpty
                          ? null
                          : () {
                              final paid = _plans.where((p) => !p.isFree).toList();
                              if (paid.isNotEmpty) _openUpgradeSheet(paid.last);
                            },
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    context.tr('choose_plan', 'Choose a plan'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Prices in TZS, billed monthly through AzamPay. Cancel any time.',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  ..._buildPlanSections(),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('payment_history', 'Payment history'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      if (_invoices.isNotEmpty)
                        Text(
                          '${_invoices.length}',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_invoices.isEmpty)
                    _EmptyInvoices()
                  else
                    ..._invoices.map(
                      (invoice) => _InvoiceTile(
                        invoice: invoice,
                        planName: _planById(invoice.planId)?.name ?? 'Subscription',
                      ),
                    ),
                  const SizedBox(height: 20),
                  _PolicyNote(),
                ],
              ),
            ),
    );
  }

  List<Widget> _buildPlanSections() {
    const groups = <String, List<String>>{
      'For buyers': ['buyer'],
      'For sellers': ['seller_basic', 'seller_plus', 'seller_pro'],
      'For businesses': ['business'],
    };
    final widgets = <Widget>[];
    for (final entry in groups.entries) {
      final plans = entry.value
          .map(_planById)
          .whereType<SubscriptionPlan>()
          .toList();
      if (plans.isEmpty) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(
          entry.key,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ));
      for (final plan in plans) {
        widgets.add(_PlanCard(
          plan: plan,
          isCurrent: _current?.planId == plan.id && _current?.isUsable == true,
          canTrial: _canTrial && !plan.isFree,
          isDowngrade: _current?.isUsable == true &&
              _currentPlan != null &&
              !_currentPlan!.isFree &&
              plan.priceTzs < _currentPlan!.priceTzs,
          onSelect: () {
            if (plan.isFree) {
              if (_current?.isUsable == true && !_current!.cancelAtPeriodEnd) {
                _downgrade(plan);
              }
              return;
            }
            _openUpgradeSheet(plan);
          },
          isPopular: plan.id == 'seller_plus',
        ));
      }
    }
    return widgets;
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({
    required this.subscription,
    required this.plan,
    required this.entitlements,
    this.onCancel,
    this.onResume,
  });

  final UserSubscription? subscription;
  final SubscriptionPlan? plan;
  final Map<String, dynamic>? entitlements;
  final VoidCallback? onCancel;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = subscription?.status ?? 'inactive';
    final usable = status == 'active' || status == 'trialing';
    final name = plan?.name ??
        entitlements?['planName']?.toString() ??
        'Free plan';
    final end = subscription?.effectiveEnd;

    return Card(
      elevation: 0,
      color: cs.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'CURRENT PLAN',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              name,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              plan == null
                  ? 'Included with your account'
                  : plan!.isFree
                      ? 'Free — no billing'
                      : '${plan!.priceLabel} / month',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onPrimaryContainer.withValues(alpha: 0.85),
              ),
            ),
            if (subscription?.isCancelling == true) ...[
              const SizedBox(height: 12),
              _InlineNote(
                icon: Icons.schedule,
                text: end == null
                    ? 'Cancellation is scheduled.'
                    : 'Ends on ${_formatDate(end)}. You keep access until then.',
                color: cs.onPrimaryContainer,
              ),
            ],
            if (subscription?.pendingDowngradePlanId != null) ...[
              const SizedBox(height: 8),
              _InlineNote(
                icon: Icons.swap_horiz,
                text:
                    'Switches to another plan on ${_formatDate(end)}.',
                color: cs.onPrimaryContainer,
              ),
            ],
            if (subscription?.isTrialing == true && subscription?.trialEndsAt != null) ...[
              const SizedBox(height: 8),
              _InlineNote(
                icon: Icons.timer_outlined,
                text:
                    'Trial ends ${_formatDate(subscription!.trialEndsAt)}. Add a payment method to keep it.',
                color: cs.onPrimaryContainer,
              ),
            ],
            if (usable && !subscription!.isCancelling && end != null) ...[
              const SizedBox(height: 8),
              _InlineNote(
                icon: Icons.event_repeat,
                text: 'Renews on ${_formatDate(end)}',
                color: cs.onPrimaryContainer,
              ),
            ],
            if (onCancel != null || onResume != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  if (onResume != null)
                    FilledButton.tonalIcon(
                      onPressed: onResume,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Resume plan'),
                    ),
                  if (onCancel != null)
                    TextButton(
                      onPressed: onCancel,
                      child: const Text('Cancel subscription'),
                    ),
                ],
              ),
            ],
            if (plan != null && plan!.features.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: plan!.features
                    .take(6)
                    .map((f) => Chip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          label: Text(
                            _featureLabel(f),
                            style: const TextStyle(fontSize: 11),
                          ),
                          side: BorderSide(
                            color: cs.onPrimaryContainer.withValues(alpha: 0.2),
                          ),
                          backgroundColor:
                              cs.onPrimaryContainer.withValues(alpha: 0.06),
                          labelStyle: TextStyle(color: cs.onPrimaryContainer),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AiUsageCard extends StatelessWidget {
  const _AiUsageCard({
    required this.quota,
    required this.showUpgrade,
    this.onUpgrade,
  });

  final AiQuota quota;
  final bool showUpgrade;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = quota.exhausted
        ? cs.error
        : quota.ratio >= 0.8
            ? cs.tertiary
            : cs.primary;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: color),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'AI assistant usage today',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${quota.used}/${quota.limit}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: quota.ratio,
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              quota.exhausted
                  ? 'Daily limit reached. Resets tomorrow.'
                  : '${quota.remaining} actions left today. Resets daily.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            if (showUpgrade && onUpgrade != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: onUpgrade,
                  child: const Text('Get more AI actions'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.canTrial,
    required this.isDowngrade,
    required this.isPopular,
    required this.onSelect,
  });

  final SubscriptionPlan plan;
  final bool isCurrent;
  final bool canTrial;
  final bool isDowngrade;
  final bool isPopular;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isCurrent
              ? cs.primary
              : cs.outlineVariant.withValues(alpha: 0.5),
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isPopular && !isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'POPULAR',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: cs.onTertiaryContainer,
                      ),
                    ),
                  ),
                if (isCurrent)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('Current', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  plan.isFree ? 'Free' : plan.priceLabel,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
                if (!plan.isFree)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3, left: 4),
                    child: Text(
                      '/ month',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${plan.aiActionsPerDay} AI actions per day',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            if (plan.features.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...plan.features.take(8).map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _featureLabel(f),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: isCurrent
                  ? OutlinedButton(
                      onPressed: null,
                      child: const Text('Current plan'),
                    )
                  : plan.isFree
                      ? OutlinedButton(
                          onPressed: onSelect,
                          child: const Text('Move to free plan'),
                        )
                      : FilledButton(
                          onPressed: onSelect,
                          child: Text(
                            isDowngrade
                                ? 'Schedule downgrade'
                                : canTrial
                                    ? 'Try free for 7 days'
                                    : 'Upgrade',
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.planName});

  final SubscriptionInvoice invoice;
  final String planName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final completed = invoice.status == 'completed';
    final amount = invoice.amount.round().toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'),
          (m) => '${m[1]},',
        );
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          completed ? Icons.check_circle_outline : Icons.receipt_long_outlined,
          color: completed ? cs.primary : cs.onSurfaceVariant,
        ),
        title: Text(planName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          invoice.failureReason ??
              '${invoice.currency} $amount · ${_formatDate(invoice.createdAt)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _StatusChip(status: invoice.status),
      ),
    );
  }
}

class _EmptyInvoices extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, color: cs.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(
            'No payments yet',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            'Receipts appear here after your first paid plan.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PolicyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Subscriptions renew monthly until cancelled. Cancelling stops the '
            'next charge and keeps access until the period you already paid '
            'for ends. Paid plans require approved KYC.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              color: color.withValues(alpha: 0.9),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      'active' => ('ACTIVE', cs.primary),
      'trialing' => ('TRIAL', cs.tertiary),
      'cancel_pending' => ('CANCELLING', cs.error),
      'past_due' => ('PAST DUE', cs.error),
      'payment_failed' => ('FAILED', cs.error),
      'pending_payment' => ('PENDING', cs.tertiary),
      'expired' => ('EXPIRED', cs.onSurfaceVariant),
      _ => ('FREE', cs.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Bottom sheet for a paid plan: free trial (when eligible) or AzamPay USSD.
class _UpgradeSheet extends StatefulWidget {
  const _UpgradeSheet({
    required this.service,
    required this.plan,
    required this.allowTrial,
  });

  final SubscriptionService service;
  final SubscriptionPlan plan;
  final bool allowTrial;

  @override
  State<_UpgradeSheet> createState() => _UpgradeSheetState();
}

class _UpgradeSheetState extends State<_UpgradeSheet> {
  final TextEditingController _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _trial() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.startTrialOrThrow(widget.plan.id);
      if (!mounted) return;
      Navigator.pop(
        context,
        'Trial started. ${widget.plan.aiActionsPerDay} AI actions per day are now active.',
      );
    } on SubscriptionException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pay() async {
    final phone = _phone.text.trim();
    if (phone.length < 9) {
      setState(() => _error = 'Enter your mobile money number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ref = await widget.service.upgrade(
        planId: widget.plan.id,
        phone: phone,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        ref.isEmpty
            ? 'Payment request sent. Approve the prompt on your phone.'
            : 'Payment request sent ($ref). Approve the USSD prompt on your phone.',
      );
    } on SubscriptionException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.plan.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.plan.priceLabel} / month · ${widget.plan.aiActionsPerDay} AI actions per day',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: cs.onErrorContainer, fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _phone,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Mobile money number',
              hintText: '07XX XXX XXX',
              prefixIcon: Icon(Icons.phone_android),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The price is charged by the server through AzamPay. You will get a '
            'prompt on this number to approve it.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _pay,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Pay ${widget.plan.priceLabel} now'),
            ),
          ),
          if (widget.allowTrial) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy ? null : _trial,
                child: const Text('Start 7-day free trial instead'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => context.push(AppRoutes.kyc),
              child: const Text('KYC required for paid plans — verify now'),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime? date) {
  if (date == null) return '—';
  return DateFormat('d MMM yyyy').format(date.toLocal());
}

String _featureLabel(String key) {
  const labels = <String, String>{
    'browse': 'Browse the marketplace',
    'search': 'Search & discovery',
    'favorites': 'Save favorites',
    'buyer_requests': 'Post buyer requests',
    'flash_sales': 'Join flash sales',
    'basic_chat': 'Chat with buyers',
    'notifications': 'Push notifications',
    'seller_profile': 'Public seller shop',
    'product_listings': 'Unlimited listings',
    'order_management': 'Order management',
    'basic_analytics': 'Basic analytics',
    'ai_basic': 'AI listing help',
    'advanced_analytics': 'Advanced analytics',
    'priority_support': 'Priority support',
    'priority_ai': 'Priority AI responses',
    'seller_productivity_tools': 'Productivity tools',
    'subscription_badge': 'Verified seller badge',
    'advanced_analytics_pro': 'Pro analytics',
    'higher_quotas': 'Higher limits',
    'premium_reporting': 'Premium reports',
    'business_tools': 'Business tools',
    'team_management': 'Team management',
    'business_analytics': 'Business analytics',
    'business_reporting': 'Business reporting',
    'seller_basic': 'Everything in Seller Basic',
    'seller_plus': 'Everything in Seller Plus',
    'seller_pro': 'Everything in Seller Pro',
  };
  final label = labels[key];
  if (label != null) return label;
  final words = key.replaceAll('_', ' ');
  return words.isEmpty ? key : words[0].toUpperCase() + words.substring(1);
}
