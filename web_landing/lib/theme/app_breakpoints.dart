/// Adaptive layout from constraints (never from isPhone/isTablet flags).
enum SokoLayout { mobile, tablet, desktop, wide }

SokoLayout layoutOf(double width) {
  if (width < 600) return SokoLayout.mobile;
  if (width < 1024) return SokoLayout.tablet;
  if (width < 1440) return SokoLayout.desktop;
  return SokoLayout.wide;
}

extension SokoLayoutX on SokoLayout {
  bool get isMobile => this == SokoLayout.mobile;
  bool get isTablet => this == SokoLayout.tablet;
  bool get isDesktop => this == SokoLayout.desktop || this == SokoLayout.wide;

  /// Marketplace grid columns for the given layout.
  int get marketColumns => switch (this) {
        SokoLayout.mobile => 2,
        SokoLayout.tablet => 3,
        SokoLayout.desktop => 4,
        SokoLayout.wide => 5,
      };
}
