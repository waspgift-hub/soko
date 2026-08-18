import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../services/review_service.dart';
import '../services/profanity_filter.dart';
import '../models/review_model.dart';
import '../extensions/context_tr.dart';
import '../app/routes.dart';
import '../widgets/soko_vibe_loading.dart';

class ReviewSection extends StatefulWidget {
  final String productId;
  final String productName;
  const ReviewSection({
    super.key,
    required this.productId,
    required this.productName,
  });

  @override
  State<ReviewSection> createState() => _ReviewSectionState();
}

class _ReviewSectionState extends State<ReviewSection> {
  final ReviewService _reviewService = ReviewService();

  void _openAllReviews() {
    context.push(
      AppRoutes.productReviews,
      extra: {
        'productId': widget.productId,
        'productName': widget.productName,
      },
    );
  }

  Future<void> _writeReview() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      context.push(AppRoutes.login);
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ReviewDialog(productId: widget.productId),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('review_submitted'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Review>>(
      stream: _reviewService.getProductReviews(widget.productId),
      builder: (context, snapshot) {
        final reviews = snapshot.data ?? [];
        if (snapshot.hasError) {
          return const SizedBox.shrink();
        }

        if (reviews.isEmpty) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.tr('reviews'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: _writeReview,
                icon: const Icon(Icons.edit, size: 16),
                label: Text(context.tr('write')),
              ),
            ],
          );
        }

        final avg = reviews.fold<double>(
              0,
              (sum, r) => sum + r.rating,
            ) /
            reviews.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('reviews'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: _writeReview,
                  icon: const Icon(Icons.edit, size: 16),
                  label: Text(context.tr('write')),
                ),
              ],
            ),
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _openAllReviews,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                        avg.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Stars(rating: avg, size: 18),
                            const SizedBox(height: 4),
                            Text(
                              context.trParams('based_on_reviews', {
                                'count': '${reviews.length}',
                              }),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _openAllReviews,
                child: Text(context.tr('see_all')),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Stars extends StatelessWidget {
  final double rating;
  final double size;
  const _Stars({required this.rating, required this.size});

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

class _ReviewDialog extends StatefulWidget {
  final String productId;
  const _ReviewDialog({required this.productId});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  double _rating = 5;
  final TextEditingController _commentController = TextEditingController();
  bool _submitting = false;

  Future<void> _submit() async {
    final text = _commentController.text;
    if (text.trim().isNotEmpty) {
      final check = await ProfanityFilter().check(text);
      if (!check.clean) {
        if (mounted) {
          if (check.banned) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(check.message ?? 'Account deleted for profanity'), backgroundColor: Theme.of(context).colorScheme.error),
            );
            await FirebaseAuth.instance.signOut();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(check.message ?? 'Profanity detected'), backgroundColor: Theme.of(context).colorScheme.error),
            );
          }
        }
        return;
      }
    }
    setState(() => _submitting = true);
    try {
      await ReviewService().addReview(
        productId: widget.productId,
        rating: _rating,
        comment: _commentController.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('review_failed'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('write_review')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              return IconButton(
                icon: Icon(
                  i < _rating ? Icons.star : Icons.star_border,
                  color: Theme.of(context).colorScheme.tertiary,
                  size: 36,
                ),
                onPressed: () => setState(() => _rating = i + 1),
              );
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
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
          onPressed: _submitting
              ? null
              : () => Navigator.pop(context, false),
          child: Text(context.tr('cancel')),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SokoVibeThreeDotLoader(size: 16, dotSize: 4)
              : Text(context.tr('submit')),
        ),
      ],
    );
  }
}
