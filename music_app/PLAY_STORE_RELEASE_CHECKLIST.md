# SokoVibe Music — Google Play release checklist

This checklist is based on the current repository implementation. A successful compile is not proof that the app is ready for Google Play.

## Automated build

The `.github/workflows/flutter-music.yml` workflow is configured to:
- run Worker JavaScript syntax validation;
- generate the Android platform files used by this Flutter project;
- set Android compile SDK and target SDK to API 36;
- enable core-library desugaring required by `flutter_local_notifications`;
- run `flutter pub get`, `flutter analyze`, and `flutter test`;
- build an APK candidate using the production music Worker URL;
- smoke-test the deployed Worker health and Jamendo search; and
- build and upload a Play Store Android App Bundle only when upload signing is configured.

The APK candidate is useful for device testing. **Do not upload it to Google Play unless it is signed with the intended upload key and the release has been verified on a real device.**

## Configure Play upload signing in GitHub

Never commit a keystore or send its passwords in a chat. The repository workflow reads these GitHub Actions repository secrets:

- `ANDROID_KEYSTORE_BASE64` — base64-encoded upload keystore file.
- `ANDROID_KEYSTORE_PASSWORD` — keystore password.
- `ANDROID_KEY_ALIAS` — key alias.
- `ANDROID_KEY_PASSWORD` — key password.

Create an upload key locally and store a secure backup before configuring these secrets. On Linux, encode the keystore as one line with `base64 -w 0 upload-keystore.jks`; on other systems use the equivalent single-line base64 command. Do not lose the key or passwords. Configure all four secrets in the GitHub repository's Settings → Secrets and variables → Actions. If these secrets are absent, the workflow intentionally does not publish a Play Store AAB artifact.

Before the first public release, confirm the generated Android `applicationId` in the Gradle file and reserve that exact package name in Play Console. Do not change it after publishing.

## Deploy the Cloudflare Worker after merge

The workflow deploys the Worker only after changes reach `soko-vibe-music`; it does not deploy production code from a pull-request branch. Configure these GitHub Actions repository secrets before merging if automatic deployment is desired:

- `CLOUDFLARE_API_TOKEN` — a Cloudflare API token with permission to edit Workers Scripts for the SokoVibe account.
- `CLOUDFLARE_ACCOUNT_ID` — the account ID containing `soko-vibe-music-backend`.

The connected Cloudflare account available during this session is read-only and cannot deploy scripts. The production smoke test observed HTTP 200 from the health endpoint but HTTP 502 from music search. The current source now encodes Jamendo's multi-value `include` parameter as a space-separated list (URL-encoded as `+`), but that fix remains unverified until deployed and the post-deploy search smoke test passes.

## Play Console items that cannot be completed by a repository build

- [ ] Confirm the developer account is verified and eligible to publish.
- [ ] Confirm the final package name, app name, version code, version name, app signing and upload key.
- [ ] Upload the signed `.aab` from the successful workflow artifact.
- [ ] Publish a stable public privacy-policy URL and keep it consistent with `PRIVACY_POLICY.md` and the in-app Privacy policy screen.
- [ ] Complete the Data safety form based on actual app and provider behaviour; update it if analytics, ads, accounts, payments, uploads or other SDKs are added.
- [ ] Complete the content rating questionnaire, target audience and app-content declarations.
- [ ] Declare whether ads are present (the current app does not include an advertising SDK).
- [ ] Provide store listing text, support contact, high-resolution app icon, phone screenshots, and feature graphic.
- [ ] Test the signed release on real Android devices, including search, audio playback, network loss, offline/local audio, notifications and removal of offline files.
- [ ] Verify music-provider commercial-use, streaming, attribution and download rights for the exact intended business model. A provider API response or a downloadable flag alone is not a blanket commercial licence.
- [ ] Review Google Play pre-launch reports and resolve crashes, ANRs, policy issues and accessibility problems.
- [ ] If the developer account is a personal account created after 13 November 2023, complete the required closed test with at least 12 opted-in testers continuously for 14 days and apply for production access, if this rule applies to the account.

## Current known limitations

- The app currently has no user account system, Google sign-in, ad SDK, subscriptions, Play Billing or artist upload system. Do not advertise these as available.
- The Worker URL is `https://soko-vibe-music-backend.wapalila.workers.dev`. Cloudflare account inspection confirmed a Worker with that name, the `wapalila` workers.dev subdomain, a configured AI binding and a Jamendo client-ID secret binding. This confirms configuration exists, not that a live end-to-end playback test passed.
- The repository branch's Worker source is newer than the deployed Worker version observed in Cloudflare. Deployment could not be performed from the current Cloudflare connection because it lacks Workers Scripts write permission. Do not treat source changes as deployed until a write-enabled deployment and smoke test succeed.
- Release signing depends on owner-controlled keystore material. Never create or publish a Play Store release with a debug signing key.
- Google Play review and production access are external account-owner/reviewer steps and cannot be guaranteed by CI.

## Official policy references

- Target API requirements: https://support.google.com/googleplay/android-developer/answer/11926878
- Privacy and Data safety: https://support.google.com/googleplay/android-developer/answer/10144311
- Testing requirements for eligible new personal developer accounts: https://support.google.com/googleplay/android-developer/answer/14151465
