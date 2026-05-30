import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/flash_sale_model.dart';
import '../../services/flash_sale_service.dart';
import '../../services/whatsapp_service.dart';
import '../../extensions/context_tr.dart';
import '../../widgets/google_loading.dart';
import '../../app/routes.dart';
import 'package:cached_network_image/cached_network_image.dart';

const Color _darkGreen = Color(0xFF1B4332);
const Color _midGreen = Color(0xFF2D6A4F);
const Color _accentGreen = Color(0xFF52B788);
const Color _lightGreen = Color(0xFF95D5B2);

class FlashSaleScreen extends StatefulWidget {
  const FlashSaleScreen({super.key});

  @override
  State<FlashSaleScreen> createState() => _FlashSaleScreenState();
}

class _FlashSaleScreenState extends State<FlashSaleScreen> {
  final FlashSaleService _service = FlashSaleService();
  final WhatsAppService _whatsapp = WhatsAppService();

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    setState(() {});
    Future.delayed(const Duration(seconds: 1), _tick);
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: StreamBuilder<List<FlashSale>>(
        stream: _service.getActiveFlashSales(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: GoogleLoading(size: 32));
          }
          final sales = snapshot.data!;
          if (sales.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_fire_department, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Hakuna Flash Sale kwa sasa',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Subiri flash sale inayofuata!',
                    style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  ),
                ],
              ),
            );
          }
          return CustomScrollView(
            slivers: [
              _buildHeroBanner(sales.length),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Row(
                    children: [
                      Icon(Icons.local_fire_department, color: _accentGreen, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${sales.length} Flash Deals',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _darkGreen),
                      ),
                      const Spacer(),
                      Text(
                        'Inaisha muda wowote',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildSaleCard(sales[index]),
                  childCount: sales.length,
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroBanner(int saleCount) {
    return SliverToBoxAdapter(
      child: Container(
        height: 240,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_darkGreen, _midGreen],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 44,
              left: 0, right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => context.pop(),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -40,
              top: -40,
              child: Icon(Icons.local_fire_department, size: 200, color: Colors.white.withValues(alpha: 0.04)),
            ),
            Positioned(
              bottom: -30,
              left: -30,
              child: Icon(Icons.local_fire_department, size: 140, color: Colors.white.withValues(alpha: 0.03)),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _accentGreen.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.local_fire_department, color: _accentGreen, size: 12),
                                  const SizedBox(width: 4),
                                  const Text('SOKO LANGU', style: TextStyle(color: Color(0xFF95D5B2), fontSize: 9, letterSpacing: 1)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'FLASH SALE',
                              style: TextStyle(
                                color: _lightGreen,
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                                shadows: [Shadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(2, 3))],
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'BIG DISCOUNTS\nFLASH SALES\nLIMITED OFFERS',
                              style: TextStyle(color: Color(0xFFB7E4C7), fontSize: 11, height: 1.6, letterSpacing: 0.8),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.phone, color: _accentGreen, size: 12),
                                const SizedBox(width: 4),
                                Text('$saleCount deals live', style: const TextStyle(color: Color(0xFF95D5B2), fontSize: 10)),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _accentGreen,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text('SHOP NOW', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: _accentGreen.withValues(alpha: 0.3), width: 3),
                              ),
                              child: Center(
                                child: Icon(Icons.local_fire_department, color: _accentGreen, size: 40),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$saleCount Active',
                              style: const TextStyle(color: Color(0xFF95D5B2), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaleCard(FlashSale sale) {
    final remaining = sale.endTime.difference(DateTime.now());
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    final secs = remaining.inSeconds.remainder(60);
    final saved = sale.originalPrice - sale.salePrice;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _lightGreen.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: _darkGreen.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_midGreen, _accentGreen],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${hours}h ${minutes}m ${secs}s',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '-${sale.discountPercent.toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: sale.productImage,
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(width: 90, height: 90, color: Colors.grey[200], child: const Center(child: GoogleLoading(size: 20, strokeWidth: 2))),
                    errorWidget: (_, _, _) => Container(width: 90, height: 90, color: Colors.grey[200], child: const Icon(Icons.image, color: Colors.grey)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sale.productName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            context.formatPrice(sale.originalPrice),
                            style: TextStyle(color: Colors.grey[400], fontSize: 13, decoration: TextDecoration.lineThrough),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.formatPrice(sale.salePrice),
                            style: TextStyle(color: _accentGreen, fontWeight: FontWeight.bold, fontSize: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${context.tr('you_save')} ${context.formatPrice(saved)}',
                        style: TextStyle(color: _midGreen, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      if (sale.location.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(sale.location, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('${AppRoutes.productDetail}/${sale.productId}'),
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('Angalia'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _midGreen,
                      side: BorderSide(color: _midGreen),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _whatsapp.openWhatsApp(
                        phoneNumber: sale.sellerPhone.isNotEmpty ? sale.sellerPhone : '255700000000',
                        message: 'Habari ${sale.sellerName}, nimeona "${sale.productName}" ikiwa Flash Sale ${context.currencySymbol()} ${sale.salePrice.toStringAsFixed(0)} kwenye Soko Langu. Naomba kununua.',
                      );
                    },
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: const Text('WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
