import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'edit_profile_screen.dart';
import 'refer_screen.dart';
import 'info_content_screen.dart';
import 'screen_constants.dart';
import 'theme_controller.dart';
import 'user_cache_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final brightness = MediaQuery.platformBrightnessOf(context);
    final userStream = user == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: AppThemeController.themeMode,
        builder: (context, themeMode, _) {
          final isDark = switch (themeMode) {
            ThemeMode.dark => true,
            ThemeMode.light => false,
            ThemeMode.system => brightness == Brightness.dark,
          };

          return FutureBuilder<Map<String, String>>(
            future: UserCacheService.load(),
            builder: (context, cacheSnapshot) {
              final cached = cacheSnapshot.data ?? const <String, String>{};
              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: userStream,
                builder: (context, snapshot) {
                  final data = snapshot.data?.data();
                  if (data != null) {
                    UserCacheService.save(data);
                  }
                  final game = ((data?['game'] as String?) ?? cached['game'] ?? '').trim();
                  final gameId = ((data?['gameId'] as String?) ?? cached['gameId'] ?? '').trim();
                  final gameLevel =
                      (data?['gameLevel']?.toString() ?? cached['gameLevel'] ?? '').trim();
                  final username =
                      ((data?['username'] as String?) ?? cached['username'] ?? '').trim();
                  final name = ((data?['name'] as String?) ?? cached['name'] ?? '').trim();
                  final email = ((data?['email'] as String?) ?? cached['email'] ?? '').trim();
                  final photo = ((data?['photo'] as String?) ?? cached['photo'] ?? '').trim();

                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Center(
                        child: Column(
                          children: [
                            // const SizedBox(height: 10),
                            CircleAvatar(
                              radius: 54,
                              backgroundColor: primaryColor.withValues(alpha: 0.1),
                              backgroundImage: photo.isEmpty ? null : NetworkImage(photo),
                              child: photo.isEmpty
                                  ? const Icon(Icons.person, size: 54, color: primaryColor)
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              name.isEmpty ? (user?.displayName ?? 'Player') : name,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              email.isEmpty ? (user?.email ?? '') : email,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _ProfileInfoTile(
                        label: 'Game',
                        value: game.isEmpty ? 'Not set' : game,
                        icon: Icons.sports_esports,
                        trailing: gameLevel.isEmpty
                            ? null
                            : Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: primaryColor.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  'Lv : $gameLevel',
                                  style: const TextStyle(
                                    color: primaryColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      _ProfileInfoTile(
                        label: 'Game ID',
                        value: gameId.isEmpty ? 'Not set' : gameId,
                        icon: Icons.badge_outlined,
                        trailing: gameId.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: gameId));
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Game ID copied'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded),
                                tooltip: 'Copy',
                              ),
                      ),
                      const SizedBox(height: 12),
                      _ProfileInfoTile(
                        label: 'Username',
                        value: username.isEmpty ? 'Not set' : username,
                        icon: Icons.alternate_email_rounded,
                        trailing: username.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: username));
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Username copied'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_rounded),
                                tooltip: 'Copy',
                              ),
                      ),
                      const SizedBox(height: 20),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Dark mode'),
                        value: isDark,
                        onChanged: AppThemeController.setDarkMode,
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person, color: primaryColor),
                        title: const Text('Edit Profile'),
                        subtitle: Text(
                          'Update your profile detail',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EditProfileScreen(
                                currentName: name,
                                currentUsername: username,
                                currentGame: game,
                                currentGameId: gameId,
                                currentGameLevel: gameLevel,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.gavel_rounded, color: primaryColor),
                        title: const Text('Battle Rules'),
                        subtitle: Text(
                          'Tap to read how battles work',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const InfoContentScreen(
                                title: 'Battle Rules',
                                sections: [
                                  InfoSection(
                                    title: 'Fair Play Policy',
                                    content: [
                                      'Use of any third-party tools or hacks is strictly prohibited.',
                                      'Teaming up with opponents in solo matches will lead to a permanent ban.',
                                      'Abusing bugs or glitches to gain an unfair advantage is not allowed.',
                                    ],
                                  ),
                                  InfoSection(
                                    title: 'Match Conduct',
                                    content: [
                                      'Ensure a stable internet connection before joining a battle.',
                                      'Only Solo Arena matches are accepted. Duo or Squad matches are strictly prohibited.',
                                      'Playing in a Duo/Squad will result in rejection of the submission and zero rewards.',
                                      'Quitting a match early may result in zero rewards and loss of entry fee.',
                                      'Respect all players and maintain a healthy gaming environment.',
                                    ],
                                  ),
                                  InfoSection(
                                    title: 'Rewards & Payouts',
                                    content: [
                                      'Coins are automatically credited after match verification.',
                                      'In case of disputes, the decision of the DuelXZone team is final.',
                                      'Physical rewards (for Mega/Weekly) require valid profile details.',
                                      'In case of a tie (equal points), the player with the higher game level is declared the winner.',
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.privacy_tip_rounded, color: primaryColor),
                        title: const Text('Privacy Policy'),
                        subtitle: Text(
                          'Read how we handle your data',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        onTap: () async {
                          final uri = Uri.parse('https://docs.google.com/document/d/12C_QloFvNJfYhn2Zr-c0eD0vMGYoQn4CQaAae1A0JBs/edit?usp=sharing');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } else {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Unable to open link')),
                            );
                          }
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_rounded, color: primaryColor),
                        title: const Text('Terms & Conditions'),
                        subtitle: Text(
                          'Important usage conditions',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const InfoContentScreen(
                                title: 'Terms & Conditions',
                                sections: [
                                  InfoSection(
                                    title: 'License & Access',
                                    content: [
                                      'DuelXZone grants you a limited, non-exclusive license to use the app for personal entertainment.',
                                      'Users must be at least 13 years of age to participate in tournaments.',
                                    ],
                                  ),
                                  InfoSection(
                                    title: 'Coin System',
                                    content: [
                                      'Coins are virtual currency and hold no real-world cash value.',
                                      'Transfer of coins between accounts is not permitted.',
                                      'DuelXZone reserves the right to reset or modify coin balances in case of suspicious activity.',
                                    ],
                                  ),
                                  InfoSection(
                                    title: 'Account Security',
                                    content: [
                                      'You are responsible for maintaining the confidentiality of your account.',
                                      'Each person is allowed only one registered account.',
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.help_outline_rounded, color: primaryColor),
                        title: const Text('Help & Support'),
                        subtitle: Text(
                          'Contact us for any issues',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        onTap: () async {
                          final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
                          final encodedSubject = Uri.encodeComponent('Support Request: $username ($uid)');
                          final uri = Uri.parse('mailto:supportduelXZone@gmail.com?subject=$encodedSubject');
                          try {
                            // Try launching directly, as canLaunchUrl is sometimes unreliable on Android 11+
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not open email app. Please mail to supportduelXZone@gmail.com'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.people_rounded, color: primaryColor),
                        title: const Text('Refer App'),
                        subtitle: Text(
                          'Invite friends & earn 100 coins',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ReferScreen(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                        title: const Text(
                          'Logout',
                          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Sign out of your account',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        onTap: () => _showLogoutDialog(context),
                      ),
                      const SizedBox(height: 28),
                      FutureBuilder<PackageInfo>(
                        future: PackageInfo.fromPlatform(),
                        builder: (context, snapshot) {
                          final version = snapshot.data?.version ?? '1.0.0';
                          return Center(
                            child: Text(
                              'DuelXZone v$version\n© ${DateTime.now().year} DuelXZone. All rights reserved.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.4),
                                    fontWeight: FontWeight.w600,
                                    height: 1.5,
                                  ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseAuth.instance.signOut();
              await GoogleSignIn.instance.signOut();
            },
            child: const Text(
              'Logout',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfoTile extends StatelessWidget {
  const _ProfileInfoTile({
    required this.label,
    required this.value,
    required this.icon,
    this.trailing,
  });

  final String label;
  final String value;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? cardBackground
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: primaryColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          trailing ?? const SizedBox.shrink(),
        ],
      ),
    );
  }
}
