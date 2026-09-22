import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Stylized Android app preview: search bar, chips, mini product rows.
/// Pure Flutter widgets — no fake screenshots.
class PhoneMockup extends StatelessWidget {
  final String searchHint;
  final List<String> chips;

  const PhoneMockup({
    super.key,
    required this.searchHint,
    required this.chips,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 290,
      height: 590,
      decoration: BoxDecoration(
        color: SokoBrand.black,
        borderRadius: BorderRadius.circular(48),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 50,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: Container(
        decoration: BoxDecoration(
          color: SokoBrand.white,
          borderRadius: BorderRadius.circular(40),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            Center(
              child: Container(
                width: 90,
                height: 22,
                decoration: BoxDecoration(
                  color: SokoBrand.black,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: SokoBrand.black,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'S',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Soko Vibe',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  const Icon(Icons.notifications_outlined, size: 20),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F5F4),
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.search,
                        size: 18, color: SokoBrand.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        searchHint,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SokoBrand.muted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.mic_none,
                        size: 18, color: SokoBrand.deepGreen),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                itemCount: chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: i == 0 ? SokoBrand.black : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color:
                          i == 0 ? SokoBrand.black : SokoBrand.line,
                    ),
                  ),
                  child: Text(
                    chips[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: i == 0 ? Colors.white : SokoBrand.ink,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 3,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: SokoBrand.line),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F5F4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.image_outlined,
                          color: SokoBrand.muted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Bar(width: 110),
                            SizedBox(height: 6),
                            _Bar(width: 70),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.verified,
                        size: 16,
                        color: SokoBrand.deepGreen,
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
}

class _Bar extends StatelessWidget {
  final double width;
  const _Bar({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 10,
      decoration: BoxDecoration(
        color: const Color(0xFFE7E7E4),
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}
