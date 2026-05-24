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
  Timer? _resolveTimer;
  int _waitingSecondsLeft = 30;
  Timer? _waitingTimer;
  bool _submittingReSearch = false;

  void _startWaitingTimer() {
    if (_waitingTimer != null) return;
    _waitingSecondsLeft = 30;
    _waitingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_waitingSecondsLeft > 0) {
          _waitingSecondsLeft--;
        } else {
          _stopWaitingTimer();
          _handleWaitingTimeout();
        }
      });
    });
  }

  void _stopWaitingTimer() {
    _waitingTimer?.cancel();
    _waitingTimer = null;
  }

  Future<void> _handleWaitingTimeout() async {
    try {
      await BattleService.leaveBattle(widget.battleId);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('No opponent found. Search again.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _cancelAndReSearch() async {
    setState(() => _submittingReSearch = true);
    try {
      await BattleService.leaveBattle(widget.battleId);
      if (!mounted) return;
      Navigator.of(context).pop('re-search');
    } catch (e) {
      if (mounted) {
        setState(() => _submittingReSearch = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Failed to cancel match: $e'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _resolveTimer?.cancel();
    _stopWaitingTimer();
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

        final status = battle['status'] as String? ?? 'waiting';
        if (status == 'waiting') {
          _startWaitingTimer();
        } else {
          _stopWaitingTimer();
        }

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
                waitingSecondsLeft: _waitingSecondsLeft,
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
                Row(
                  children: [
                    Expanded(
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
                          disabledBackgroundColor: primaryColor.withValues(alpha: 0.45),
                          disabledForegroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: Text(iStarted ? 'Waiting for Opponent...' : 'Start Battle'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: _submittingReSearch ? null : _cancelAndReSearch,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryColor,
                        side: const BorderSide(color: primaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: _submittingReSearch
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: primaryColor),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ],
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
                loading: false,
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SubmitResultSheet(
        onSubmit: (file, kills, rank) async {
          await BattleService.uploadBattleProof(
            battleId: widget.battleId,
            file: file,
            kills: kills,
            rank: rank,
          );
        },
      ),
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.status,
    required this.entryFee,
    required this.resultText,
    required this.timeLeft,
    this.waitingSecondsLeft,
  });

  final String status;
  final int entryFee;
  final String resultText;
  final Duration timeLeft;
  final int? waitingSecondsLeft;

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
              if (status == 'waiting' && waitingSecondsLeft != null)
                _StatusPill(label: 'Searching: ${waitingSecondsLeft}s left')
              else if (status != 'waiting')
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

class _SubmitResultSheet extends StatefulWidget {
  const _SubmitResultSheet({required this.onSubmit});

  final Future<void> Function(File file, int kills, String rank) onSubmit;

  @override
  State<_SubmitResultSheet> createState() => _SubmitResultSheetState();
}

class _SubmitResultSheetState extends State<_SubmitResultSheet> {
  final _killsController = TextEditingController();
  String? _selectedRank;
  String? _imagePath;
  bool _submitting = false;

  @override
  void dispose() {
    _killsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() => _imagePath = path);
  }

  Future<void> _handleSubmit() async {
    if (_imagePath == null) {
      _showMessage('Please select a screenshot proof.');
      return;
    }
    final kills = int.tryParse(_killsController.text.trim());
    if (kills == null || kills < 0) {
      _showMessage('Please enter a valid kills count.');
      return;
    }
    if (_selectedRank == null) {
      _showMessage('Please select your rank.');
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.onSubmit(File(_imagePath!), kills, _selectedRank!);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: primaryColor,
          content: Text('Result submitted successfully'),
        ),
      );
    } catch (e) {
      _showMessage('$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16161C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Submit Result',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Enter your match results below. Screenshot proof is mandatory.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
            ),
            const SizedBox(height: 20),
            // Screenshot picker
            Text(
              'Screenshot Proof',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _submitting ? null : _pickImage,
                icon: Icon(_imagePath == null ? Icons.image_outlined : Icons.check_circle_outline_rounded),
                label: Text(_imagePath == null ? 'Select Screenshot' : 'Screenshot Added'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _imagePath == null ? primaryColor : Colors.green,
                  side: BorderSide(
                    color: _imagePath == null ? primaryColor.withValues(alpha: 0.3) : Colors.green.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            if (_imagePath != null) ...[
              const SizedBox(height: 4),
              Text(
                'Selected: ${_imagePath!.split(Platform.pathSeparator).last}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            // Kills
            TextField(
              controller: _killsController,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Kills',
                hintText: 'Enter number of kills',
              ),
            ),
            const SizedBox(height: 16),
            // Rank dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedRank,
              onChanged: _submitting ? null : (val) => setState(() => _selectedRank = val),
              decoration: const InputDecoration(
                labelText: 'Rank',
                hintText: 'Select your rank',
              ),
              items: const [
                DropdownMenuItem(value: '1', child: Text('1')),
                DropdownMenuItem(value: '2-5', child: Text('2-5')),
                DropdownMenuItem(value: '6-10', child: Text('6-10')),
                DropdownMenuItem(value: '11-20', child: Text('11-20')),
                DropdownMenuItem(value: '21+', child: Text('21+')),
              ],
            ),
            const SizedBox(height: 24),
            // Warning warning
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Once submitted, results cannot be modified or resubmitted.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Submit button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _handleSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit Result',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}