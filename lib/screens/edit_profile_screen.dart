import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screen_constants.dart';
import 'user_cache_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.currentName,
    required this.currentUsername,
    required this.currentGame,
    required this.currentGameId,
    required this.currentGameLevel,
  });

  final String currentName;
  final String currentUsername;
  final String currentGame;
  final String currentGameId;
  final String currentGameLevel;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static final _usernamePattern = RegExp(r'^[a-z][a-z0-9._]*$');

  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _gameIdController;
  late final TextEditingController _gameLevelController;

  String? _selectedGame;
  bool _isSaving = false;
  String? _errorText;
  String? _usernameError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _usernameController = TextEditingController(text: widget.currentUsername);
    _selectedGame = widget.currentGame.isEmpty ? null : widget.currentGame;
    _gameIdController = TextEditingController(text: widget.currentGameId);
    _gameLevelController = TextEditingController(text: widget.currentGameLevel);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _gameIdController.dispose();
    _gameLevelController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final gameId = _gameIdController.text.trim();
    final levelStr = _gameLevelController.text.trim();
    final level = int.tryParse(levelStr);

    if (username.isEmpty || _selectedGame == null || gameId.isEmpty || levelStr.isEmpty) {
      setState(() => _errorText = 'All fields are required.');
      return;
    }

    if (!_usernamePattern.hasMatch(username)) {
      setState(() => _usernameError = 'Start with letter, use lowercase, numbers, _ or .');
      return;
    }

    if (level == null || level < 20) {
      setState(() => _errorText = 'Minimum level 20 required.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
      _usernameError = null;
    });

    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty && query.docs.first.id != user.uid) {
        setState(() => _usernameError = 'Username is already taken');
        return;
      }

      final data = {
        'name': name,
        'username': username,
        'game': _selectedGame,
        'gameId': gameId,
        'gameLevel': level,
      };

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        data,
        SetOptions(merge: true),
      );

      await UserCacheService.save(data);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: primaryColor,
        ),
      );
      Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      if (e.code == 'permission-denied') {
        setState(() => _usernameError = 'Permission denied. Allow read in Firestore rules.');
      } else {
        setState(() => _errorText = e.message ?? 'Unable to save profile.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = 'An unexpected error occurred.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          if (_errorText != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Text(
                _errorText!,
                style: TextStyle(
                  color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Display Name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: 'Username',
              prefixIcon: const Icon(Icons.alternate_email_rounded),
              helperText: 'Start with letter, use lowercase, numbers, _ or .',
              errorText: _usernameError,
            ),
            onChanged: (value) {
              if (_usernameError != null) {
                setState(() => _usernameError = null);
              }
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Select Game',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _GameSelectCard(
                  name: 'BGMI',
                  icon: Icons.sports_esports,
                  selected: _selectedGame == 'BGMI',
                  onTap: () => setState(() => _selectedGame = 'BGMI'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _GameSelectCard(
                  name: 'Free Fire',
                  icon: Icons.local_fire_department,
                  selected: _selectedGame == 'Free Fire',
                  onTap: () => setState(() => _selectedGame = 'Free Fire'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _gameIdController,
            decoration: InputDecoration(
              labelText: _selectedGame != null ? '$_selectedGame ID' : 'Game ID',
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _gameLevelController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: _selectedGame != null ? '$_selectedGame Level' : 'Game Level',
              prefixIcon: const Icon(Icons.show_chart),
              helperText: 'Required minimum level 20',
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save Changes',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameSelectCard extends StatelessWidget {
  const _GameSelectCard({
    required this.name,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? primaryColor.withValues(alpha: 0.12)
              : (isDark ? cardBackground : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? primaryColor : primaryColor.withValues(alpha: 0.1),
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? primaryColor : Colors.grey,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: selected
                    ? primaryColor
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
