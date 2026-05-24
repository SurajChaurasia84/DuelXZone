import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'screen_constants.dart';
import 'tournament_service.dart';

class TournamentMatchesScreen extends StatefulWidget {
  const TournamentMatchesScreen({
    super.key,
    required this.title,
    required this.cycleId,
    required this.liveStart,
    required this.battleCount,
  });

  final String title;
  final String cycleId;
  final DateTime liveStart;
  final int battleCount;

  @override
  State<TournamentMatchesScreen> createState() => _TournamentMatchesScreenState();
}

class _TournamentMatchesScreenState extends State<TournamentMatchesScreen> {
  Timer? _timer;
  DateTime _now = DateTime.now();
  int? _joiningBattle;
  int? _uploadBattle;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: TournamentService.participantStream(widget.cycleId),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data == null) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: const Center(child: Text('Only registered players can join these battles')),
          );
        }

        final matchIds = <String>[];
        for (var index = 1; index <= widget.battleCount; index++) {
          final battleData =
              Map<String, dynamic>.from((data['battle$index'] as Map<String, dynamic>?) ?? {});
          final matchId = (battleData['matchId'] as String?)?.trim() ?? '';
          if (matchId.isNotEmpty) {
            matchIds.add(matchId);
          }
        }

        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              _TournamentInfoHeader(
                battleCount: widget.battleCount,
                activeMatches: matchIds.length,
              ),
              const SizedBox(height: 18),
              for (var index = 1; index <= widget.battleCount; index++) ...[
                _BattleSlot(
                  cycleId: widget.cycleId,
                  battleNumber: index,
                  currentUserId: snapshot.data!.id,
                  battleData:
                      Map<String, dynamic>.from((data['battle$index'] as Map<String, dynamic>?) ?? {}),
                  now: _now,
                  joining: _joiningBattle == index,
                  uploadingScreenshot: _uploadBattle == index,
                  onJoin: () => _joinBattle(index),
                  onUpload: (roomId) => _pickAndUpload(
                    battleNumber: index,
                    roomId: roomId,
                  ),
                ),
                if (index != widget.battleCount) const SizedBox(height: 14),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _joinBattle(int battleNumber) async {
    setState(() => _joiningBattle = battleNumber);
    try {
      final roomId = await TournamentService.joinOrCreateBattleRoom(
        cycleId: widget.cycleId,
        battleNumber: battleNumber,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: primaryColor,
          content: Text('Battle $battleNumber ready in room $roomId'),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'not-found' => 'Only registered players can join this battle.',
        'already-joined' => 'You already joined this battle.',
        _ => e.message ?? 'Unable to join match right now.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _joiningBattle = null);
    }
  }

  Future<void> _pickAndUpload({
    required int battleNumber,
    required String roomId,
  }) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SubmitResultSheet(
        onSubmit: (file, kills, rank) async {
          await TournamentService.uploadBattleProof(
            cycleId: widget.cycleId,
            battleNumber: battleNumber,
            roomId: roomId,
            file: file,
            kills: kills,
            rank: rank,
          );
        },
      ),
    );
  }
}

class _TournamentInfoHeader extends StatelessWidget {
  const _TournamentInfoHeader({
    required this.battleCount,
    required this.activeMatches,
  });

  final int battleCount;
  final int activeMatches;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6A38), primaryColor, Color(0xFF8F2A0A)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$battleCount ${battleCount == 1 ? 'Battle' : 'Battles'}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Random matchmaking works only for players registered in this tournament cycle.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
          ),
          const SizedBox(height: 14),
          _HeaderPill(label: '$activeMatches/$battleCount battles joined'),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.label});

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
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _BattleSlot extends StatelessWidget {
  const _BattleSlot({
    required this.cycleId,
    required this.battleNumber,
    required this.currentUserId,
    required this.battleData,
    required this.now,
    required this.joining,
    required this.uploadingScreenshot,
    required this.onJoin,
    required this.onUpload,
  });

  final String cycleId;
  final int battleNumber;
  final String currentUserId;
  final Map<String, dynamic> battleData;
  final DateTime now;
  final bool joining;
  final bool uploadingScreenshot;
  final VoidCallback onJoin;
  final void Function(String roomId) onUpload;

  @override
  Widget build(BuildContext context) {
    final roomId = (battleData['matchId'] as String?)?.trim() ?? '';
    if (roomId.isEmpty) {
      return _TournamentBattleCard(
        title: 'Battle $battleNumber',
        statusLabel: 'NOT JOINED',
        subtitle: 'Join to get matched with a random registered player.',
        action: FilledButton(
          onPressed: joining ? null : onJoin,
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
          ),
          child: joining
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Join Match'),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: TournamentService.battleRoomStream(cycleId: cycleId, roomId: roomId),
      builder: (context, snapshot) {
        final room = snapshot.data?.data() ?? <String, dynamic>{};
        final playerIds = List<String>.from(room['playerIds'] as List<dynamic>? ?? []);
        final players = Map<String, dynamic>.from(room['players'] as Map<String, dynamic>? ?? {});
        final expiresAt = room['expiresAt'];
        final endTime = expiresAt is Timestamp ? expiresAt.toDate() : null;
        final live = endTime != null && now.isBefore(endTime);
        final waiting = (room['status'] as String?) == 'waiting' || playerIds.length < 2;

        final screenshotDone = (battleData['screenshotUrl'] as String?)?.isNotEmpty == true;

        return _TournamentBattleCard(
          title: 'Battle $battleNumber',
          statusLabel: waiting ? 'WAITING' : (live ? 'LIVE' : 'CLOSED'),
          subtitle: waiting
              ? 'Waiting for another registered player to join.'
              : live
                  ? 'Ends in ${_formatDuration(endTime.difference(now))}'
                  : 'Upload window closed',
          opponents: [
            for (final entry in players.entries)
              if (entry.key != currentUserId && entry.value is Map<String, dynamic>)
                (entry.value['name'] as String?) ?? 'Player'
          ],
          action: _UploadRow(
            title: 'Screenshot',
            done: screenshotDone,
            loading: uploadingScreenshot,
            enabled: !waiting && live && !screenshotDone,
            onTap: () => onUpload(roomId),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = safe.inHours;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m ${seconds}s';
  }
}

class _TournamentBattleCard extends StatelessWidget {
  const _TournamentBattleCard({
    required this.title,
    required this.statusLabel,
    required this.subtitle,
    required this.action,
    this.opponents = const [],
  });

  final String title;
  final String statusLabel;
  final String subtitle;
  final List<String> opponents;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: isDark ? cardBackground : Colors.grey.shade100,
        border: Border.all(color: primaryColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              _StatusChip(label: statusLabel),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          if (opponents.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Opponent: ${opponents.first}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
          const SizedBox(height: 14),
          action,
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(color: primaryColor, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _UploadRow extends StatelessWidget {
  const _UploadRow({
    required this.title,
    required this.done,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final bool done;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        FilledButton(
          onPressed: enabled && !loading ? onTap : null,
          style: FilledButton.styleFrom(
            backgroundColor: done ? const Color(0xFF39D98A) : primaryColor,
            foregroundColor: Colors.white,
          ),
          child: loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(done ? 'Done' : 'Upload'),
        ),
      ],
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
