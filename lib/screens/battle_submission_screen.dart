import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'battle_submission_service.dart';
import 'screen_constants.dart';
import '../services/ad_service.dart';

class BattleSubmissionScreen extends StatefulWidget {
  const BattleSubmissionScreen({
    super.key,
    required this.cycle,
  });

  final BattleSubmissionCycle cycle;

  @override
  State<BattleSubmissionScreen> createState() => _BattleSubmissionScreenState();
}

class _BattleSubmissionScreenState extends State<BattleSubmissionScreen> {
  final TextEditingController _killsController = TextEditingController();
  int _selectedBattle = 1;
  String? _selectedRank;
  String? _imagePath;
  bool _savingBattle = false;
  bool _finalSubmitting = false;

  @override
  void dispose() {
    _killsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BattleSubmissionUser>(
      future: BattleSubmissionService.currentUserMeta(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.cycle.title)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (userSnapshot.hasError || !userSnapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.cycle.title)),
            body: const Center(child: Text('Unable to load user profile')),
          );
        }

        final user = userSnapshot.data!;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: BattleSubmissionService.participantStream(
            cycleId: widget.cycle.id,
            username: user.username,
          ),
          builder: (context, snapshot) {
            final participant = snapshot.data?.data();
            if (participant == null) {
              return Scaffold(
                appBar: AppBar(title: Text(widget.cycle.title)),
                body: const Center(child: Text('Join this battle first')),
              );
            }

            final completedBattles = <int>{
              for (var index = 1; index <= widget.cycle.battleCount; index++)
                if (BattleSubmissionService.isBattleCompleted(participant['battle$index']))
                  index,
            };
            final nextUnlocked = BattleSubmissionService.nextUnlockedBattle(
              participantData: participant,
              battleCount: widget.cycle.battleCount,
            );
            final isFinalSubmitted = participant['submittedAt'] != null;
            final showFinalSubmit = widget.cycle.battleCount > 1;

            if (_selectedBattle > nextUnlocked &&
                !completedBattles.contains(_selectedBattle)) {
              _selectedBattle = nextUnlocked;
              _loadDraft(participant, _selectedBattle);
            }

            return Scaffold(
              appBar: AppBar(title: Text(widget.cycle.title)),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'IMPORTANT: SOLO ONLY',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Only Solo Arena matches are accepted. Playing in a Duo or Squad will result in zero rewards.',
                                style: TextStyle(fontSize: 14, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: List.generate(widget.cycle.battleCount, (index) {
                      final battleNumber = index + 1;
                      final isCompleted = completedBattles.contains(battleNumber);
                      final isEnabled =
                          battleNumber <= nextUnlocked || isCompleted;
                      return ChoiceChip(
                        label: Text('Battle $battleNumber'),
                        selected: _selectedBattle == battleNumber,
                        onSelected: isEnabled
                            ? (_) {
                                setState(() {
                                  _selectedBattle = battleNumber;
                                  _loadDraft(participant, battleNumber);
                                });
                              }
                            : null,
                        selectedColor:
                            isCompleted ? Colors.green : primaryColor,
                        labelStyle: TextStyle(
                          color: _selectedBattle == battleNumber || isCompleted
                              ? Colors.white
                              : null,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  _BattleCard(
                    battleNumber: _selectedBattle,
                    battleCount: widget.cycle.battleCount,
                    completed: completedBattles.contains(_selectedBattle),
                    locked: _selectedBattle > nextUnlocked &&
                        !completedBattles.contains(_selectedBattle),
                    killsController: _killsController,
                    selectedRank: _selectedRank,
                    imagePath: _imagePath,
                    disabled: isFinalSubmitted,
                    onRankChanged: (value) => setState(() => _selectedRank = value),
                    onPickImage: _pickImage,
                  ),
                  if (showFinalSubmit)
                    const SizedBox(height: 8),
                ],
              ),
              bottomNavigationBar: SafeArea(
                minimum: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: FilledButton(
                  onPressed: isFinalSubmitted ||
                          _savingBattle ||
                          _finalSubmitting ||
                          (_selectedBattle > nextUnlocked &&
                              !completedBattles.contains(_selectedBattle))
                      ? null
                      : () => _handleBottomSubmit(
                            user: user,
                            completedBattles: completedBattles,
                          ),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.cycle.battleCount == 1
                        ? primaryColor
                        : Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: (_savingBattle || _finalSubmitting)
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          isFinalSubmitted
                              ? 'Submitted'
                              : _bottomButtonLabel(
                                  completedBattles: completedBattles,
                                ),
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() => _imagePath = path);
  }

  Future<void> _submitBattle(BattleSubmissionUser user) async {
    final kills = int.tryParse(_killsController.text.trim());
    if (kills == null || kills < 0 || _selectedRank == null) {
      _showMessage('Enter valid kills and rank.');
      return;
    }
    if (_imagePath == null) {
      _showMessage('Upload screenshot proof.');
      return;
    }

    setState(() => _savingBattle = true);
    try {
      await BattleSubmissionService.submitBattle(
        cycleId: widget.cycle.id,
        username: user.username,
        battleNumber: _selectedBattle,
        battleCount: widget.cycle.battleCount,
        kills: kills,
        rank: _selectedRank!,
        imageFile: File(_imagePath!),
      );
      if (widget.cycle.battleCount == 1) {
        await BattleSubmissionService.finalSubmit(
          cycleId: widget.cycle.id,
          username: user.username,
          battleCount: widget.cycle.battleCount,
        );
      }
      if (!mounted) return;
      _showMessage(
        widget.cycle.battleCount == 1
            ? 'Daily battle submitted successfully'
            : 'Battle $_selectedBattle submitted',
      );
      
      // Show Interstitial Ad upon successful battle submit
      AdService().showInterstitialAd();

      setState(() {
        _clearDraft();
      });
    } catch (e) {
      String msg = e.toString();
      if (e is FirebaseException) {
        msg = e.message ?? msg;
      }
      _showMessage(msg, isError: true);
    } finally {
      if (mounted) setState(() => _savingBattle = false);
    }
  }

  Future<void> _finalSubmit(BattleSubmissionUser user) async {
    setState(() => _finalSubmitting = true);
    try {
      await BattleSubmissionService.finalSubmit(
        cycleId: widget.cycle.id,
        username: user.username,
        battleCount: widget.cycle.battleCount,
      );
      if (!mounted) return;
      _showMessage('Final submission complete');
      
      // Show Interstitial Ad upon successful final submit
      AdService().showInterstitialAd();
    } catch (e) {
      String msg = e.toString();
      if (e is FirebaseException) {
        msg = e.message ?? msg;
      }
      _showMessage(msg, isError: true);
    } finally {
      if (mounted) setState(() => _finalSubmitting = false);
    }
  }

  Future<void> _handleBottomSubmit({
    required BattleSubmissionUser user,
    required Set<int> completedBattles,
  }) async {
    final isCurrentCompleted = completedBattles.contains(_selectedBattle);
    if (!isCurrentCompleted) {
      await _submitBattle(user);
      return;
    }

    if (widget.cycle.battleCount > 1 &&
        completedBattles.length == widget.cycle.battleCount) {
      await _finalSubmit(user);
    }
  }

  String _bottomButtonLabel({
    required Set<int> completedBattles,
  }) {
    if (widget.cycle.battleCount == 1) {
      return 'Submit Final Battle';
    }
    if (completedBattles.length == widget.cycle.battleCount) {
      return 'Final Submit';
    }
    return 'Submit Battle $_selectedBattle';
  }

  void _loadDraft(Map<String, dynamic> participant, int battleNumber) {
    final battle = Map<String, dynamic>.from(
      (participant['battle$battleNumber'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
    _killsController.text = battle['kills']?.toString() ?? '';
    _selectedRank = battle['rank'] as String?;
    _imagePath = null;
  }

  void _clearDraft() {
    _killsController.clear();
    _selectedRank = null;
    _imagePath = null;
  }

  void _showMessage(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red.shade800 : null,
        content: Row(
          children: [
            if (isError) ...[
              const Icon(Icons.error_outline_rounded, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _BattleCard extends StatelessWidget {
  const _BattleCard({
    required this.battleNumber,
    required this.battleCount,
    required this.completed,
    required this.locked,
    required this.killsController,
    required this.selectedRank,
    required this.imagePath,
    required this.disabled,
    required this.onRankChanged,
    required this.onPickImage,
  });

  final int battleNumber;
  final int battleCount;
  final bool completed;
  final bool locked;
  final TextEditingController killsController;
  final String? selectedRank;
  final String? imagePath;
  final bool disabled;
  final ValueChanged<String?> onRankChanged;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    final isDisabled = disabled || locked || completed;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: isDark ? cardBackground : Colors.grey.shade100,
        border: Border.all(
          color: completed
              ? Colors.green
              : primaryColor.withValues(alpha: 0.12),
          width: completed ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Battle $battleNumber',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              if (completed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Completed',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (locked) ...[
            const SizedBox(height: 12),
            const Text('Complete the previous battle first.'),
          ],
          const SizedBox(height: 16),
          _UploadSection(
            label: 'Image',
            buttonLabel: imagePath == null ? 'Upload Image' : 'Image Added',
            icon: Icons.image_outlined,
            enabled: !isDisabled,
            onTap: onPickImage,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: killsController,
            enabled: !isDisabled,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Kills',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: selectedRank,
            onChanged: isDisabled ? null : onRankChanged,
            decoration: const InputDecoration(
              labelText: 'Rank',
            ),
            items: const [
              DropdownMenuItem(value: '1', child: Text('1')),
              DropdownMenuItem(value: '2-5', child: Text('2-5')),
              DropdownMenuItem(value: '6-10', child: Text('6-10')),
              DropdownMenuItem(value: '11-20', child: Text('11-20')),
              DropdownMenuItem(value: '21+', child: Text('21+')),
            ],
          ),
        ],
      ),
    );
  }
}

class _UploadSection extends StatelessWidget {
  const _UploadSection({
    required this.label,
    required this.buttonLabel,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String buttonLabel;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: enabled ? onTap : null,
            icon: Icon(icon),
            label: Text(buttonLabel),
          ),
        ),
      ],
    );
  }
}
