import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'battle_room_screen.dart';
import 'battle_service.dart';
import 'battles_screen.dart';
import 'coin_badge.dart';
import 'coin_service.dart';
import 'leaderboard_screen.dart';
import 'screen_constants.dart';
import 'notification_screen.dart';
import 'tournament_matches_screen.dart';
import 'tournament_service.dart';
import 'user_cache_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _bonusHandled = false;

  Future<void> _showSignupBonus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _bonusHandled || !mounted) return;

    _bonusHandled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: primaryColor,
          content: const Text(
            'Signup Bonus +500 coins added to your wallet',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      );

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'signupBonusPending': false,
      }, SetOptions(merge: true));
    });
  }

  Future<void> _showPlayOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose Battle Entry',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'You will be matched with any ready player in the same tier.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                _PlayOptionTile(
                  label: 'Free Battle',
                  amount: 0,
                  reward: 20,
                  onTap: () {
                    Navigator.pop(context);
                    _startBattle(0);
                  },
                ),
                const SizedBox(height: 10),
                _PlayOptionTile(
                  label: '30 Coin Battle',
                  amount: 30,
                  reward: 60,
                  onTap: () {
                    Navigator.pop(context);
                    _startBattle(30);
                  },
                ),
                const SizedBox(height: 10),
                _PlayOptionTile(
                  label: '50 Coin Battle',
                  amount: 50,
                  reward: 100,
                  onTap: () {
                    Navigator.pop(context);
                    _startBattle(50);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _startBattle(int entryFee) async {
    try {
      final existingBattleId = await BattleService.findLiveBattleId();
      if (existingBattleId != null) {
        if (!mounted) return;
        final openRoom = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Room Already Live'),
              content: const Text(
                'A room is already live. Exit that room before joining another.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Later'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Open Room'),
                ),
              ],
            );
          },
        );

        if (openRoom == true && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BattleRoomScreen(battleId: existingBattleId),
            ),
          );
        }
        return;
      }

      final battleId = await BattleService.createOrJoinBattle(entryFee: entryFee);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BattleRoomScreen(battleId: battleId),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'active-room-exists' =>
          'A room is already live. Exit that room before joining another.',
        'permission-denied' =>
          'Battle room permission denied. Please update Firestore rules for battles.',
        'unauthenticated' => 'Please sign in again.',
        _ => e.message ?? 'Unable to start battle right now.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(''),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return FutureBuilder<Map<String, String>>(
      future: UserCacheService.load(),
      builder: (context, cacheSnapshot) {
        final cached = cacheSnapshot.data ?? const <String, String>{};
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: user == null
              ? null
              : FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data();
            if (data != null) {
              UserCacheService.save(data);
            }
            if (data?['signupBonusPending'] == true) {
              _showSignupBonus();
            }

            final username =
                (data?['username'] as String?)?.trim().isNotEmpty == true
                ? (data?['username'] as String).trim()
                : (cached['username']?.trim().isNotEmpty == true
                      ? cached['username']!.trim()
                      : (user?.displayName ?? cached['name'] ?? 'Player')
                            .trim());
            final photoUrl =
                (data?['photo'] as String?)?.trim().isNotEmpty == true
                ? (data?['photo'] as String).trim()
                : ((cached['photo']?.trim().isNotEmpty == true
                      ? cached['photo']!.trim()
                      : user?.photoURL));

            return Scaffold(
              appBar: AppBar(
                titleSpacing: 20,
                title: _TopBarTitle(username: username, photoUrl: photoUrl),
                actions: [
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NotificationScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.notifications_none_rounded),
                  ),
                  const CoinBadge(),
                  const SizedBox(width: 16),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  const _TournamentBanner(),
                  const SizedBox(height: 22),
                  _PrimaryPlayButton(onTap: _showPlayOptions),
                  const SizedBox(height: 18),
                  _LeaderboardSection(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LeaderboardScreen(),
                        ),
                      );
                    },
                  ),
                  const _TournamentActionSection(),
                  Text(
                    'Active Room',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _MyBattleRoomsSection(),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TopBarTitle extends StatelessWidget {
  const _TopBarTitle({required this.username, required this.photoUrl});

  final String username;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: primaryColor.withValues(alpha: 0.14),
          backgroundImage: (photoUrl ?? '').isEmpty
              ? null
              : NetworkImage(photoUrl!),
          child: (photoUrl ?? '').isEmpty
              ? const Icon(Icons.person, color: primaryColor)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Welcome Back',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              Text(
                username,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TournamentBanner extends StatelessWidget {
  const _TournamentBanner();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55FF4B11),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/bg.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) {
                  return const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF2A120B),
                          Color(0xFF631C09),
                          Color(0xFFB2380C),
                        ],
                      ),
                    ),
                  );
                },
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.06),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.34),
                    ],
                    stops: const [0, 0.45, 1],
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 18,
                child: SizedBox(
                  height: 52,
                  width: 52,
                  child: Image.asset(
                    'assets/icon.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.sports_esports_rounded,
                        color: Colors.white,
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Play, win & earn coins as you dominate your rivals.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const BattlesScreen(),
                          ),
                        );
                      },
                      child: Text(
                        'See battles >',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: primaryColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryPlayButton extends StatelessWidget {
  const _PrimaryPlayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          elevation: 0,
        ),
        child: Text(
          'Quick Play',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

// class _QuickActionButton extends StatelessWidget {
//   const _QuickActionButton({
//     required this.title,
//     required this.icon,
//     required this.onTap,
//   });

//   final String title;
//   final IconData icon;
//   final VoidCallback onTap;

//   @override
//   Widget build(BuildContext context) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;

//     return InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(22),
//       child: Container(
//         padding: const EdgeInsets.all(16),
//         decoration: BoxDecoration(
//           borderRadius: BorderRadius.circular(22),
//           color: isDark ? cardBackground : Colors.grey.shade100,
//           border: Border.all(color: primaryColor.withValues(alpha: 0.14)),
//         ),
//         child: Column(
//           children: [
//             Container(
//               height: 48,
//               width: 48,
//               decoration: BoxDecoration(
//                 color: primaryColor.withValues(alpha: 0.12),
//                 borderRadius: BorderRadius.circular(14),
//               ),
//               child: Icon(icon, color: primaryColor),
//             ),
//             const SizedBox(height: 12),
//             Text(
//               title,
//               textAlign: TextAlign.center,
//               style: Theme.of(
//                 context,
//               ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

class _PlayOptionTile extends StatelessWidget {
  const _PlayOptionTile({
    required this.label,
    required this.amount,
    required this.reward,
    required this.onTap,
  });

  final String label;
  final int amount;
  final int reward;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: isDark ? cardBackground : Colors.grey.shade100,
          border: Border.all(color: primaryColor.withValues(alpha: 0.14)),
        ),
        child: Row(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.flash_on_rounded, color: primaryColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.emoji_events_rounded, color: Color(0xFF39D98A), size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Win $reward coins',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF39D98A),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                amount == 0 ? 'FREE' : '-$amount',
                style: const TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardSection extends StatelessWidget {
  const _LeaderboardSection({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: isDark ? cardBackground : Colors.grey.shade100,
          border: Border.all(color: primaryColor.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.emoji_events_rounded, color: primaryColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Leaderboard',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'See top players and latest rankings.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded, color: primaryColor),
          ],
        ),
      ),
    );
  }
}

class _MyBattleRoomsSection extends StatelessWidget {
  const _MyBattleRoomsSection();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: BattleService.myBattlesStream(),
      builder: (context, snapshot) {
        final docs = (snapshot.data ?? const []).where((doc) {
          final data = doc.data();
          final status = data['status'] as String? ?? 'waiting';
          final dismissedBy = List<String>.from(
            data['dismissedBy'] as List<dynamic>? ?? [],
          );
          return uid != null &&
              !dismissedBy.contains(uid) &&
              (status == 'waiting' ||
                  status == 'matched' ||
                  status == 'ongoing');
        }).toList();
        if (docs.isEmpty) {
          return const Text('No active rooms right now');
        }

        final doc = docs.first;
        return _BattleRoomTile(data: doc.data(), battleId: doc.id);
      },
    );
  }
}

class _BattleRoomTile extends StatelessWidget {
  const _BattleRoomTile({required this.data, required this.battleId});

  final Map<String, dynamic> data;
  final String battleId;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // final playerIds = List<String>.from(data['playerIds'] as List<dynamic>? ?? []);
    final players = Map<String, dynamic>.from(
      (data['players'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
    String opponentName = 'Waiting for opponent...';
    for (final entry in players.entries) {
      if (entry.key != uid) {
        final player = Map<String, dynamic>.from(
          entry.value as Map<String, dynamic>,
        );
        opponentName = (player['name'] as String?) ?? opponentName;
        break;
      }
    }
    final status = data['status'] as String? ?? 'waiting';
    final canExit = uid != null && (status == 'waiting' || status == 'matched');
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BattleRoomScreen(battleId: battleId),
          ),
        );
      },
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Theme.of(context).brightness == Brightness.dark
              ? cardBackground
              : Colors.grey.shade100,
          border: Border.all(color: primaryColor.withValues(alpha: 0.12)),
        ),
        child: Stack(
          children: [
            Row(
              children: [
                Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        primaryColor.withValues(alpha: 0.9),
                        const Color(0xFFFF7B4D),
                      ],
                    ),
                  ),
                  child: const Icon(Icons.shield_rounded, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 82),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          opponentName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Entry Fee: ${(data['entryFee'] as num?)?.toInt() ?? 0} coins',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: -6,
              right: -6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (canExit)
                    IconButton(
                      onPressed: () async {
                        final shouldExit = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) {
                            return AlertDialog(
                              title: Text(
                                status == 'matched'
                                    ? 'Exit Room?'
                                    : 'Cancel Room?',
                              ),
                              content: Text(
                                status == 'matched'
                                    ? 'Leave this matched room? If you paid entry, your coins will be refunded.'
                                    : 'No opponent has joined yet. Delete this room?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(false),
                                  child: const Text('No'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(true),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text(
                                    status == 'matched' ? 'Exit' : 'Delete',
                                  ),
                                ),
                              ],
                            );
                          },
                        );

                        if (shouldExit != true) return;

                        try {
                          await BattleService.leaveBattle(battleId);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              content: Text(
                                status == 'matched'
                                    ? 'Room exited successfully'
                                    : 'Waiting room deleted',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              content: Text('$e'),
                            ),
                          );
                        }
                      },
                      tooltip: status == 'matched'
                          ? 'Exit room'
                          : 'Delete waiting room',
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.redAccent,
                    )
                  else
                    const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      status.toUpperCase(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: primaryColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _TournamentActionSection extends StatelessWidget {
  const _TournamentActionSection();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TournamentJoinAction?>(
      stream: TournamentService.joinActionStream(),
      builder: (context, snapshot) {
        final action = snapshot.data;
        if (action == null) return const SizedBox(height: 32);

        return Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 26),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: Theme.of(context).brightness == Brightness.dark
                ? cardBackground
                : Colors.grey.shade100,
            border: Border.all(color: primaryColor.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.flash_on_rounded, color: primaryColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You are registered. Continue to your battles.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TournamentMatchesScreen(
                        title: action.title,
                        cycleId: action.cycleId,
                        liveStart: action.liveStart,
                        battleCount: action.battleCount,
                      ),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Join Battles'),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}
