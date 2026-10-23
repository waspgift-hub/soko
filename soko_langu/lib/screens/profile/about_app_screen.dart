import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as url;
import '../../extensions/context_tr.dart';

/// Official Soko Vibe public links, in one place.
///
/// These were previously inline string literals scattered through this screen,
/// which is how the About screen ended up pointing at a YouTube handle that is
/// not the Soko Vibe channel, and at a personal gmail address that appears in
/// no other Soko Vibe document. Anything shown to a user as a way to reach us
/// lives here so the app and the website cannot drift apart again.

/// Support address, as published on the website and in the privacy notice.
const String supportEmail = 'support@soko-vibe.com';

/// Data Protection Officer, as published in the privacy notice.
const String dpoEmail = 'dpo@soko-vibe.com';

/// Public website.
const String websiteUrl = 'https://www.sokovibe.co.tz';

/// Terms of Service.
const String termsUrl = '$websiteUrl/terms.html';

/// Privacy Policy.
const String privacyPolicyUrl = '$websiteUrl/privacy.html';

/// YouTube channel, referenced by channel id rather than @handle: handles get
/// changed and reused, a channel id never points somewhere else.
const String youTubeChannelId = 'UC8ALYEifcm4hEsl9MGoCD4Q';
const String youTubeChannelUrl =
    'https://www.youtube.com/channel/$youTubeChannelId';

/// What to show under the YouTube row.
///
/// Not a URL: the channel's canonical form is the /channel/UC... URL and it
/// exposes no @handle, so any handle-shaped string here would be a guess that
/// could point somewhere else one day. The channel name is the honest label.
const String youTubeChannelLabel = 'Soko Vibe — YouTube';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('about')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 30),

              // Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: Image.asset(
                  'assets/app_icon.png',
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              ),

              const SizedBox(height: 20),

              // App Name
              Text(
                context.tr('app_name'),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),

              const SizedBox(height: 8),

              // Tagline
              Text(
                context.tr('tagline'),
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),

              const SizedBox(height: 40),

              // Version
              _buildInfoCard(
                context,
                icon: Icons.info_outline,
                title: context.tr('version_label'),
                value: context.tr('version'),
              ),

              const SizedBox(height: 12),

              // Credits — Founder / Developers / Investors
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    _creditRow(
                      context,
                      icon: Icons.emoji_events,
                      label: context.tr('founder_label'),
                      value: context.tr('founder_name'),
                    ),
                    const Divider(height: 20),
                    _creditRow(
                      context,
                      icon: Icons.code,
                      label: context.tr('developer'),
                      value: context.tr('developer_names'),
                    ),
                    const Divider(height: 20),
                    _creditRow(
                      context,
                      icon: Icons.handshake_outlined,
                      label: context.tr('investors_label'),
                      value: context.tr('investors_names'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Contact Email.
              // support@soko-vibe.com is the address the website, the privacy
              // notice and the data-protection notice all publish. It used to be
              // a personal gmail here, which meant a user who read the policy on
              // the site and emailed the app was talking to two different places.
              GestureDetector(
                onTap: () async {
                  final uri = Uri.parse('mailto:$supportEmail');
                  if (await url.canLaunchUrl(uri)) {
                    await url.launchUrl(uri);
                  }
                },
                child: _buildInfoCard(
                  context,
                  icon: Icons.email,
                  title: context.tr('contact_label'),
                  value: supportEmail,
                  isLink: true,
                ),
              ),

              const SizedBox(height: 12),

              // YouTube channel.
              // The channel id is the stable identifier: the @handle has been
              // changed before and would silently send users to a dead page.
              GestureDetector(
                onTap: () async {
                  final uri = Uri.parse(youTubeChannelUrl);
                  if (await url.canLaunchUrl(uri)) {
                    await url.launchUrl(
                      uri,
                      mode: url.LaunchMode.externalApplication,
                    );
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.shade400.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.play_circle_fill,
                          color: Colors.red.shade600,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('tutorials_title'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              youTubeChannelLabel,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.red.shade600,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.open_in_new,
                        color: Colors.red.shade400,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Features
              _buildInfoCard(
                context,
                icon: Icons.star,
                title: context.tr('features'),
                value: context.tr('features_text'),
              ),

              const SizedBox(height: 40),

              // Gift message
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      context.tr('thank_you'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('thank_you_message'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Copyright
              Text(
                context.tr('copyright'),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _creditRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    bool isLink = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: isLink
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                    decoration: isLink ? TextDecoration.underline : null,
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
