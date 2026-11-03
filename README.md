# SokoVibe Marketplace

SokoVibe is a Tanzania-focused marketplace for buyers and sellers. This repository is the **Marketplace product only**.

## Product scope

- Buyer and seller accounts, profiles, discovery and product listings
- Buyer requests, seller responses and in-app chat
- Orders, checkout, delivery and receipts
- Flash sales, product boosts, subscriptions and advertising
- Identity verification, blue-tick review and account safety
- Marketplace administration, moderation and reporting
- Payments, escrow, wallet balance and transaction ledger as **internal marketplace services**, not a separate Wallet application

Music streaming and a standalone Wallet client are not part of this repository's product scope.

## Repository layout

- `soko_langu/`: Flutter Marketplace application and its supporting server code
- `payment-system/`: payment integration and orchestration
- `wallet_worker/`: internal wallet/payment service used by Marketplace flows
- `offline_ussd/`: offline/USSD support where applicable
- `.github/workflows/`: Marketplace and payment validation workflows
- `docs/MARKETPLACE_SCOPE.md`: scope and architecture boundaries

## Development

See [the Flutter application guide](soko_langu/README.md) for setup commands. Run validation from `soko_langu/`:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Payment services have their own configuration and tests. Do not commit production secrets; configure them in the relevant deployment environment.

## Scope rule

Do not add music-player/streaming features or a standalone wallet app here. Keep payment and wallet capabilities that are required for marketplace checkout, escrow, refunds, payouts and transaction history.
