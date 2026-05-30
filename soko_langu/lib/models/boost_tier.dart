enum BoostTier {
  bronze,
  silver,
  gold;

  String get displayName {
    switch (this) {
      case BoostTier.bronze:
        return 'Bronze';
      case BoostTier.silver:
        return 'Silver';
      case BoostTier.gold:
        return 'Gold';
    }
  }

  int get durationDays {
    switch (this) {
      case BoostTier.bronze:
        return 3;
      case BoostTier.silver:
        return 7;
      case BoostTier.gold:
        return 30;
    }
  }

  int get priceTzs {
    switch (this) {
      case BoostTier.bronze:
        return 1500;
      case BoostTier.silver:
        return 3000;
      case BoostTier.gold:
        return 10000;
    }
  }

  double get pricePerDay {
    switch (this) {
      case BoostTier.bronze:
        return 500;
      case BoostTier.silver:
        return 429;
      case BoostTier.gold:
        return 333;
    }
  }

  String get tagline {
    switch (this) {
      case BoostTier.bronze:
        return 'Quick exposure';
      case BoostTier.silver:
        return 'Best value';
      case BoostTier.gold:
        return 'Maximum reach';
    }
  }

  static BoostTier fromString(String value) {
    switch (value.toLowerCase()) {
      case 'bronze':
        return BoostTier.bronze;
      case 'silver':
        return BoostTier.silver;
      case 'gold':
        return BoostTier.gold;
      default:
        return BoostTier.bronze;
    }
  }
}
