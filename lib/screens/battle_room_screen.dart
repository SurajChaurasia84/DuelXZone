import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'battle_service.dart';
import 'screen_constants.dart';

class BattleRoomScreen extends StatefulWidget {
  const BattleRoomScreen({
    super.key,
    required this.battleId,
  });

  final String battleId;

  @override
  State<BattleRoomScreen> createState() => _BattleRoomScreenState();
}

class _BattleRoomScreenState extends State<BattleRoomScreen> {
  bool _uploadingScreenshot = false;
  Timer? _resolveTimer;

  @override
  void dispose() {
    _resolveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<dynamic>(
      stream: BattleService.battleStream(widget.battleId),
      builder: (context, snapshot) {
        final battle = snapshot.data?.data();
        if (battle == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Battle Room')),
            body: const Center(child: Text('Battle room not found')),
          );
        }

        _scheduleResolve(battle['expiresAt']);

        final playerIds = List<String>.from(battle['playerIds'] as List<dynamic>? ?? []);
        final players = Map<String, dynamic>.from(
          (battle['players'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        );
        final me = uid == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(
                (players[uid] as Map<String, dynamic>?) ?? <String, dynamic>{},
              );
        String? opponentId;
        if (uid != null) {
          for (final id in playerIds) {
            if (id != uid) {
              opponentId = id;
              break;
            }
          }
        }
        final opponent = opponentId == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(
                (players[opponentId] as Map<String, dynamic>?) ?? <String, dynamic>{},
              );

        final status = battle['status'] as String? ?? 'waiting';
        final startedPlayerIds = List<String>.from(
          battle['startPlayerIds'] as List<dynamic>? ?? [],
        );
        final iStarted = uid != null && startedPlayerIds.contains(uid);
        final expiresAt = battle['expiresAt'] is Timestamp
            ? (battle['expiresAt'] as Timestamp).toDate()
            : null;
        final timeLeft = expiresAt == null ? Duration.zero : expiresAt.difference(DateTime.now());
        final screenshotDone = (me['screenshotUrl'] as String?)?.isNotEmpty == true;
        final canUpload =
            status == 'ongoing' || status == 'pending_admin' || status == 'review';
        final canExitRoom = status == 'waiting' || status == 'matched';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Battle Room'),
            actions: [
              if (canExitRoom)
                IconButton(
                  onPressed: () => _confirmExitRoom(status),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: status == 'matched' ? 'Exit room' : 'Delete waiting room',
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              _RoomHeader(
                status: status,
                entryFee: (battle['entryFee'] as num?)?.toInt() ?? 0,
                resultText: (battle['resultText'] as String?) ?? '',
                timeLeft: timeLeft,
              ),
              const SizedBox(height: 18),
              _BattleResultCard(
                battle: battle,
                players: players,
              ),
              const SizedBox(height: 18),
              _PlayerCard(
                title: 'You',
                name: (me['name'] as String?)?.trim().isNotEmpty == true
                    ? me['name'] as String
                    : 'Player',
                photoUrl: me['photo'] as String?,
                isReady: screenshotDone,
                started: iStarted,
              ),
              const SizedBox(height: 12),
              _PlayerCard(
                title: 'Opponent',
                name: opponentId == null
                    ? 'Waiting for player...'
                    : ((opponent['name'] as String?)?.trim().isNotEmpty == true
                        ? opponent['name'] as String
                        : 'Player'),
                photoUrl: opponent['photo'] as String?,
                isReady: (opponent['screenshotUrl'] as String?)?.isNotEmpty == true,
                started: opponentId != null && startedPlayerIds.contains(opponentId),
              ),
              if (status == 'matched') ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: iStarted
                        ? null
                        : () async {
                            try {
                              await BattleService.startBattle(widget.battleId);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: primaryColor,
                                  content: Text(
                                    startedPlayerIds.length + 1 >= playerIds.length
                                        ? 'Battle started'
                                        : 'Start confirmed. Waiting for opponent.',
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
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(iStarted ? 'Waiting for Opponent Start' : 'Start Battle'),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Submit Before Time Ends',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              _UploadCard(
                title: 'Upload Screenshot',
                subtitle: screenshotDone
                    ? 'Uploaded'
                    : canUpload
                        ? 'Pick your screenshot proof'
                        : 'Uploads unlock after both players start',
                icon: Icons.image_rounded,
                loading: _uploadingScreenshot,
                done: screenshotDone,
                onTap: screenshotDone || !canUpload || status == 'completed'
                    ? null
                    : _pickAndUpload,
              ),
            ],
          ),
        );
      },
    );
  }

  void _scheduleResolve(dynamic expiresRaw) {
    final expiresAt = expiresRaw is Timestamp ? expiresRaw.toDate() : null;
    if (expiresAt == null) return;
    final timeLeft = expiresAt.difference(DateTime.now());
    if (timeLeft.isNegative) {
      BattleService.resolveBattleIfPossible(widget.battleId);
      return;
    }

    _resolveTimer?.cancel();
    _resolveTimer = Timer(timeLeft + const Duration(seconds: 1), () {
      BattleService.resolveBattleIfPossible(widget.battleId);
    });
  }

  Future<void> _confirmExitRoom(String status) async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(status == 'matched' ? 'Exit Room?' : 'Cancel Room?'),
          content: Text(
            status == 'matched'
                ? 'Leave this matched room? If you paid entry, your coins will be refunded.'
                : 'No opponent has joined yet. Delete this room?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
              ),
              child: Text(status == 'matched' ? 'Exit' : 'Delete'),
            ),
          ],
        );
      },
    );

    if (shouldExit != true || !mounted) return;

    try {
      await BattleService.leaveBattle(widget.battleId);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            status == 'matched' ? 'Room exited successfully' : 'Waiting room deleted',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('$e'),
        ),
      );
    }
  }

  Future<void> _pickAndUpload() async {
    setState(() {
      _uploadingScreenshot = true;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
      );
      final path = result?.files.single.path;
      if (path == null) return;

      await BattleService.uploadBattleProof(
        battleId: widget.battleId,
        file: File(path),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: primaryColor,
          content: const Text('Screenshot uploaded'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('$e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploadingScreenshot = false;
        });
      }
    }
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.status,
    required this.entryFee,
    required this.resultText,
    required this.timeLeft,
  });

  final String status;
  final int entryFee;
  final String resultText;
  final Duration timeLeft;

  @override
  Widget build(BuildContext context) {
    final minutes = timeLeft.inMinutes.clamp(0, 999);
    final seconds = (timeLeft.inSeconds % 60).clamp(0, 59);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6A38), primaryColor, Color(0xFF8F2A0A)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55FF4B11),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Entry Fee: $entryFee coins',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            resultText.isEmpty ? 'Room active' : resultText,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatusPill(label: status.toUpperCase()),
              const SizedBox(width: 10),
              _StatusPill(label: '${minutes}m ${seconds}s left'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.title,
    required this.name,
    required this.photoUrl,
    required this.isReady,
    required this.started,
  });

  final String title;
  final String name;
  final String? photoUrl;
  final bool isReady;
  final bool started;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: isDark ? cardBackground : Colors.grey.shade100,
        border: Border.all(color: primaryColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage:
                (photoUrl ?? '').isEmpty ? null : NetworkImage(photoUrl!),
            child: (photoUrl ?? '').isEmpty ? const Icon(Icons.person) : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          Icon(
            isReady
                ? Icons.verified_rounded
                : started
                    ? Icons.play_circle_fill_rounded
                    : Icons.hourglass_top_rounded,
            color: isReady
                ? const Color(0xFF39D98A)
                : started
                    ? primaryColor
                    : primaryColor,
          ),
        ],
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  const _UploadCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.loading,
    required this.done,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool loading;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: isDark ? cardBackground : Colors.grey.shade100,
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
            child: Icon(icon, color: primaryColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(subtitle),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: loading || done ? null : onTap,
            style: FilledButton.styleFrom(
              backgroundColor: done ? const Color(0xFF39D98A) : primaryColor,
              foregroundColor: Colors.white,
            ),
            child: loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(done ? 'Done' : 'Upload'),
          ),
        ],
      ),
    );
  }
}

class _BattleResultCard extends StatelessWidget {
  const _BattleResultCard({
    required this.battle,
    required this.players,
  });

  final Map<String, dynamic> battle;
  final Map<String, dynamic> players;

  @override
  Widget build(BuildContext context) {
    final status = battle['status'] as String? ?? 'waiting';
    final approvedByAdmin = battle['approvedByAdmin'] == true;
    final winnerId = approvedByAdmin
        ? (battle['winnerId'] as String?) ?? (battle['winnerCandidateId'] as String?)
        : null;
    String winnerName = 'Pending';

    if (winnerId != null && players[winnerId] is Map<String, dynamic>) {
      winnerName = (Map<String, dynamic>.from(players[winnerId] as Map<String, dynamic>)['name']
              as String?) ??
          'Player';
    } else if (approvedByAdmin && winnerId == null && status == 'completed') {
      winnerName = 'No winner';
    }

    final title = switch (status) {
      'review' => 'Both players submitted proof',
      'pending_admin' => 'Waiting for admin approval',
      'completed' when approvedByAdmin => 'Winner: $winnerName',
      'completed' => 'Battle completed',
      'ongoing' => 'Battle in progress',
      'matched' => 'Players matched',
      _ => 'Waiting for opponent',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Theme.of(context).brightness == Brightness.dark
            ? cardBackground
            : Colors.grey.shade100,
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_rounded, color: primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text((battle['resultText'] as String?) ?? ''),
              ],
            ),
          ),
        ],
      ),
    );
  }
}