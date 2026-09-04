import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/product_model.dart';
import '../../extensions/context_tr.dart';
import '../../theme/app_dimens.dart';
import '../auth_wall.dart';
import '../../theme/app_typography.dart';
import '../ds/ds.dart';

/// Social-commerce feed post: seller header, big media, price, social
/// actions and commerce actions in one card. Parents wire persistence
/// (wishlist, follows, chat, checkout) through the callbacks.
class FeedPostCard extends StatefulWidget {
  final Product product;
  final bool isLiked;
  final bool isSaved;
  final bool isFollowing;
  final bool showFollowButton;
  final int likeCount;
  final int commentCount;
  final String? badgeLabel;
  final double? displayPrice;
  final double? strikethroughPrice;
  final VoidCallback? onTap;
  final VoidCallback? onChat;
  final VoidCallback? onBuy;
  final ValueChanged<bool>? onLike;
  final ValueChanged<bool>? onSave;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final ValueChanged<bool>? onFollow;
  final VoidCallback? onMore;
  final VoidCallback? onSellerTap;

  const FeedPostCard({
    super.key,
    required this.product,
    this.isLiked = false,
    this.isSaved = false,
    this.isFollowing = false,
    this.showFollowButton = true,
    this.likeCount = 0,
    this.commentCount = 0,
    this.badgeLabel,
    this.displayPrice,
    this.strikethroughPrice,
    this.onTap,
    this.onChat,
    this.onBuy,
    this.onLike,
    this.onSave,
    this.onComment,
    this.onShare,
    this.onFollow,
    this.onMore,
    this.onSellerTap,
  });

  @override
  State<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends State<FeedPostCard> {
  late bool _liked = widget.isLiked;
  late bool _saved = widget.isSaved;
  late bool _following = widget.isFollowing;
  int _page = 0;
  final _pageCtrl = PageController();

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  String get _initials {
    final name = widget.product.sellerName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    return (parts.first.characters.first +
            (parts.length > 1
                ? parts.last.characters.first
                : ''))
        .toUpperCase();
  }

  bool get _guest => FirebaseAuth.instance.currentUser == null;

  Future<bool> _guard() async {
    if (_guest) {
      await requireAuth(context);
      return false;
    }
    return true;
  }

  void _share() {
    if (FirebaseAuth.instance.currentUser == null) {
      requireAuth(context);
      return;
    }
    widget.onShare ??
        Share.share(
          '${widget.product.name} - ${widget.product.price} TZS kwenye Soko Vibe',
        );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final cs = Theme.of(context).colorScheme;
    final images = p.images.isEmpty ? const [''] : p.images;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2,
      ),
      child: DsCard(
        padding: EdgeInsets.zero,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, cs),
          const SizedBox(height: AppSpacing.s2),
          _media(context, cs, images),
          const SizedBox(height: AppSpacing.s2),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: widget.onTap,
                  child: Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.appBarTitle(cs.onSurface),
                  ),
                ),
                const SizedBox(height: 4),
                DsPrice(
                  price: widget.displayPrice ?? p.price,
                  oldPrice: widget.strikethroughPrice,
                ),
                const SizedBox(height: AppSpacing.s2),
                _actions(context, cs),
                const SizedBox(height: AppSpacing.s2),
                _commerce(context),
                const SizedBox(height: AppSpacing.s1),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _header(BuildContext context, ColorScheme cs) {
    final p = widget.product;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.s3, AppSpacing.s3, AppSpacing.s2, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onSellerTap,
            child: DsAvatar(initials: _initials),
          ),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: GestureDetector(
              onTap: widget.onSellerTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.sellerName.isEmpty
                              ? 'Muuzaji'
                              : p.sellerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.statusChip(cs.onSurface),
                        ),
                      ),
                      if (p.sellerKycApproved) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.verified,
                            size: 14, color: cs.primary),
                      ],
                    ],
                  ),
                  if (p.location.isNotEmpty)
                    Text(
                      p.district.isNotEmpty
                          ? '${p.district}, ${p.location}'
                          : p.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.timeIndicator(
                          cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
          if (widget.showFollowButton)
            TextButton(
              onPressed: () async {
                if (!await _guard()) return;
                setState(() => _following = !_following);
                widget.onFollow?.call(_following);
              },
              child: Text(_following
                  ? context.tr('following', 'Following')
                  : context.tr('follow', 'Follow')),
            ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: widget.onMore,
          ),
        ],
      ),
    );
  }

  Widget _media(
      BuildContext context, ColorScheme cs, List<String> images) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: () async {
        if (!await _guard()) return;
        setState(() => _liked = true);
        widget.onLike?.call(true);
      },
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: images.length,
              onPageChanged: (i) =>
                  setState(() => _page = i),
              itemBuilder: (_, i) => images[i].isEmpty
                  ? Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.image,
                          size: 64,
                          color: cs.onSurfaceVariant),
                    )
                  : Image.network(
                      images[i],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (ctx, err, stack) => Container(
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.broken_image,
                            size: 64,
                            color: cs.onSurfaceVariant),
                      ),
                    ),
            ),
          ),
          if (widget.badgeLabel != null)
            Positioned(
              top: 8,
              left: 8,
              child: DsBadge(
                  label: widget.badgeLabel!, color: cs.primary),
            ),
          if (widget.product.isBoosted)
            const Positioned(
              top: 8,
              right: 8,
              child: DsBoostBadge(),
            ),
          if (images.length > 1)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_page + 1}/${images.length}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, ColorScheme cs) {
    return Row(
      children: [
        DsLikeButton(
          isLiked: _liked,
          onPressed: () async {
            if (!await _guard()) return;
            setState(() => _liked = !_liked);
            widget.onLike?.call(_liked);
          },
        ),
        if (widget.likeCount > 0)
          Text('${widget.likeCount}',
              style: AppTypography.timeIndicator(
                  cs.onSurfaceVariant)),
        IconButton(
          icon: const Icon(Icons.mode_comment_outlined),
          onPressed: widget.onComment == null
              ? null
              : () async {
                  if (!await _guard()) return;
                  widget.onComment!();
                },
        ),
        if (widget.commentCount > 0)
          Text('${widget.commentCount}',
              style: AppTypography.timeIndicator(
                  cs.onSurfaceVariant)),
        IconButton(
          icon: Icon(_saved
              ? Icons.bookmark
              : Icons.bookmark_border),
          onPressed: () async {
            if (!await _guard()) return;
            setState(() => _saved = !_saved);
            widget.onSave?.call(_saved);
          },
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.share_outlined),
          onPressed: _share,
        ),
      ],
    );
  }

  Widget _commerce(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DsButton(
            label: context.tr('chat_seller', 'Chat Seller'),
            variant: DsButtonVariant.secondary,
            onPressed: widget.onChat == null
                ? null
                : () async {
                    if (!await _guard()) return;
                    widget.onChat!();
                  },
          ),
        ),
        const SizedBox(width: AppSpacing.s2),
        Expanded(
          child: DsButton(
            label: context.tr('buy_now', 'Buy Now'),
            variant: DsButtonVariant.primary,
            onPressed: widget.onBuy == null
                ? null
                : () async {
                    if (!await _guard()) return;
                    widget.onBuy!();
                  },
          ),
        ),
      ],
    );
  }
}
