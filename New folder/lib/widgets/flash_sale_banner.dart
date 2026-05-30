import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/flash_sale_model.dart';
import '../services/flash_sale_service.dart';
import '../screens/ai/ai_assistant_screen.dart';

class FlashSaleBanner extends StatelessWidget {
  const FlashSaleBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FlashSale>>(
      stream: FlashSaleService().getActiveFlashSales(),
      builder: (context, snapshot) {
        final sales = snapshot.data ?? [];
        if (sales.isEmpty) return const SizedBox.shrink();

        final topSale = sales.first;
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiAssistantScreen()),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF2D6A4F),
                  Color(0xFF40916C),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2D6A4F).withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          if (topSale.productImage.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: CachedNetworkImage(
                                imageUrl: topSale.productImage,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                                placeholder: (ctx, url) => _buildPlaceholder(),
                                errorWidget: (ctx, url, err) => _buildPlaceholder(),
                              ),
                            )
                          else
                            _buildPlaceholder(),
                          Positioned(
                            top: -4,
                            right: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '-${topSale.discountPercent.toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.local_fire_department,
                                    color: Color(0xFF2D6A4F),
                                    size: 14,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'FLASH SALE',
                                    style: TextStyle(
                                      color: Color(0xFF2D6A4F),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              topSale.productName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  'TSh ${topSale.originalPrice.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'TSh ${topSale.flashPrice.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Colors.yellow,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  color: Colors.white70,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${topSale.timeRemaining.inHours}h ${topSale.timeRemaining.inMinutes % 60}m zilibaki',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.shopping_cart,
                                        color: Color(0xFF2D6A4F),
                                        size: 12,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Nunua Sasa',
                                        style: TextStyle(
                                          color: Color(0xFF2D6A4F),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.yellow,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_bag,
            color: Colors.white,
            size: 32,
          ),
          SizedBox(height: 4),
          Text(
            'FLASH',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
