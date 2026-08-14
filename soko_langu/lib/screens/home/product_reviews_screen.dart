import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/review_service.dart';
import '../../models/review_model.dart';
import '../../extensions/context_tr.dart';
import '../../utils/network_error.dart';
import '../../widgets/soko_vibe_states.dart';
import '../../widgets/soko_vibe_loading.dart';

class ProductReviewsScreen extends StatefulWidget {
  final String productId;
  final String productName;

  const ProductReviewsScreen({
    super.key,
    required this.productId,
    required this.productName,
  });

  @override
  State<ProductReviewsScreen> createState() => _ProductReviewsScreenState();
}

class _ProductReviewsScreenState extends State<ProductReviewsScreen> {
  final ReviewService _reviewService = ReviewService();
  String? _currentUserId;
  String? _productSellerId;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _loadProductSellerId();
  }

  Future<void> _loadProductSellerId() async {
    try {
      final doc = await _reviewService.getProductSellerId(widget.productId);
      if (mounted) setState(() => _productSellerId = doc);
    } catch (_) {}
  }

  bool get _isSeller => _currentUserId != null && _productSellerId == _currentUserId;

  Future<void> _writeReview() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    double rating = 5;
    final commentController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(context.tr('write_review')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return IconButton(
                    icon: Icon(
                      i < rating ? Icons.star : Icons.star_border,
                      color: Theme.of(context).colorScheme.tertiary,
                      size: 36,
                    ),
                    onPressed: () => setDialogState(() => rating = i + 1),
                  );
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: commentController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: context.tr('share_experience'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.tr('submit')),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      try {
        await _reviewService.addReview(
          productId: widget.productId,
          rating: rating,
          comment: commentController.text,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('review_submitted'))),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(translateError(e))));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('all_reviews'))),
      body: StreamBuilder<List<Review>>(
        stream: _reviewService.getProductReviews(widget.productId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return SokoVibeErrorState(
              onRetry: () => setState(() {}),
            );
          }
          final reviews = snapshot.data;
          if (reviews == null) {
            return const Center(child: SokoVibeThreeDotLoader());
          }

          if (reviews.isEmpty) {
            return SokoVibeEmptyState(
              icon: Icons.star_border_rounded,
              title: context.tr('no_reviews_yet'),
              actionLabel: context.tr('write_review'),
              onAction: _writeReview,
            );
          }

          final total = reviews.length;
          final avg =
              reviews.fold<double>(0, (sum, r) => sum + r.rating) / total;
          final starCounts = List<int>.generate(5, (i) {
            final star = 5 - i;
            return reviews.where((r) => r.rating.round() == star).length;
          });

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      avg.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _StarRow(rating: avg, size: 26),
                    const SizedBox(height: 6),
                    Text(
                      context.trParams('based_on_reviews', {'count': '$total'}),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...List.generate(5, (i) {
                      final star = 5 - i;
                      final count = starCounts[i];
                      final pct = total == 0 ? 0.0 : count / total;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 32,
                              child: Text(
                                '$star',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(Icons.star, size: 14, color: Colors.amber),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct,
                                  minHeight: 6,
                                  backgroundColor: cs.surfaceContainerHighest,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 32,
                              child: Text(
                                '${(pct * 100).round()}%',
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _writeReview,
                        icon: const Icon(Icons.rate_review_outlined, size: 18),
                        label: Text(context.tr('write_review')),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ...reviews.map((r) => _ReviewTile(
                    review: r,
                    isSeller: _isSeller,
                    onHelpful: () => _toggleHelpful(r),
                    onReply: _isSeller
                        ? () => _replyToReview(r)
                        : null,
                  )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _toggleHelpful(Review review) async {
    try {
      await _reviewService.toggleHelpful(
        review.id,
        isLiked: review.hasLiked,
      );
    } catch (_) {}
  }

  Future<void> _replyToReview(Review review) async {
    final controller = TextEditingController(
      text: review.sellerReply ?? '',
    );
    final reply = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('reply_label')),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: context.tr('write_reply_hint'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text.trim().isEmpty ? null : controller.text.trim()),
            child: Text(context.tr('submit')),
          ),
        ],
      ),
    );
    if (reply != null) {
      try {
        await _reviewService.replyToReview(review.id, reply);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('reply_submitted'))),
          );
        }
      } catch (_) {}
    }
  }
}

class _StarRow extends StatelessWidget {
  final double rating;
  final double size;
  const _StarRow({required this.rating, required this.size});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.round();
        return Icon(
          filled ? Icons.star : Icons.star_border,
          size: size,
          color: Colors.amber,
        );
      }),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final Review review;
  final bool isSeller;
  final VoidCallback onHelpful;
  final VoidCallback? onReply;
  const _ReviewTile({
    required this.review,
    required this.isSeller,
    required this.onHelpful,
    this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: cs.primary,
                child: review.userImage != null && review.userImage!.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          review.userImage!,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              Icon(Icons.person, size: 24, color: cs.onPrimary),
                        ),
                      )
                    : Icon(Icons.person, size: 24, color: cs.onPrimary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.userName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (review.isVerifiedPurchase) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.verified,
                            size: 13,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            context.tr('verified_purchase'),
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              _StarRow(rating: review.rating, size: 14),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            review.comment.isEmpty ? '—' : review.comment,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.85),
              height: 1.4,
            ),
          ),
          if (review.sellerReply != null && review.sellerReply!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('seller_reply_label'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    review.sellerReply!,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                _formatDate(review.createdAt),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              if (onReply != null) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onReply,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.reply_outlined,
                          size: 15,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          context.tr('reply_label'),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onHelpful,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        review.hasLiked
                            ? Icons.thumb_up_rounded
                            : Icons.thumb_up_outlined,
                        size: 15,
                        color: review.hasLiked
                            ? cs.primary
                            : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${context.tr('helpful')}${review.helpfulCount > 0 ? ' (${review.helpfulCount})' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: review.hasLiked
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return "${dt.day}/${dt.month}/${dt.year}";
  }
}
