# Marketplace product scope

## Product boundary

This repository contains SokoVibe Marketplace only. It is not a monorepo for the separate SokoVibe Music product or a standalone Wallet app.

## In scope

- Buyer/seller onboarding, authentication, profiles and verification
- Product catalogue, discovery, search, seller listings and product media
- Buyer requests, messaging and notifications
- Orders, checkout, fulfilment, returns and receipts
- Flash sales, boosts, subscriptions and advertising monetisation
- Admin operations, moderation, KYC review, reports and audit trails
- Payment orchestration, escrow, wallet ledger, refunds and seller payouts when required by marketplace transactions

## Out of scope

- Music catalogue, audio streaming, local music player, music accounts and music-specific Supabase data
- Standalone Wallet mobile application and its APK distribution

## Architecture guardrails

1. Marketplace payments and wallet ledger are internal services. Do not remove them merely because the standalone Wallet app is out of scope.
2. Marketplace client routes and navigation must not expose music features.
3. Keep only dependencies required by Marketplace functionality. Remove a dependency only after checking imports and platform configuration.
4. Firebase/Firestore remains the marketplace data/auth direction unless a separately reviewed migration explicitly changes it.
5. Treat payment providers and payment-worker APIs as server-side integrations. Never embed private provider credentials in the Flutter client.
6. Keep historical/requirements documentation until its unique information has been consolidated and checked; do not delete documents solely because their names look duplicated.

## Validation required before release

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- Android release build
- Firestore security rules and indexes review
- Payment webhook signature, idempotency, ledger reconciliation and payout tests
- End-to-end buyer purchase and seller fulfilment tests

A successful source cleanup is not proof that these checks pass.
