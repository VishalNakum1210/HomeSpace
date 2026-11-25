import 'package:flutter/material.dart';
import '../design/album_widgets.dart';
import '../design/space_theme.dart';
import '../design/space_widgets.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';

class AdminUsersPage extends StatefulWidget {
  final HomeRepository repository;
  const AdminUsersPage({super.key, required this.repository});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  List<FamilyAccount> _users = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final list = await widget.repository.getFamilyAccounts();
      if (mounted) {
        setState(() {
          _users = List.of(list);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e.toString();
        });
      }
    }
  }

  Future<void> _showAddUserDialog() async {
    final payload = await showDialog<({String name, String email, String password, AvatarTone tone, bool isAdmin})>(
      context: context,
      builder: (_) => const _AddFamilyUserDialog(),
    );
    if (payload == null || !mounted) return;
    try {
      await widget.repository.createFamilyMember(
        name: payload.name,
        email: payload.email,
        password: payload.password,
        avatarTone: payload.tone,
        isAdmin: payload.isAdmin,
      );
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Added ${payload.name} to family accounts.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Failed to add user: $e'),
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteUser(FamilyAccount user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${user.name}?'),
        content: Text(
          'Are you sure you want to remove ${user.name} (${user.email}) from HomeSpace?\n\nTheir account and personal data will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD32F2F)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove User'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await widget.repository.deleteFamilyMember(user.id);
        await _loadUsers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Removed ${user.name}.'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Failed to remove: $e'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = SpaceStyle.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Management'),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-family-member-btn'),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Member'),
        onPressed: _showAddUserDialog,
      ),
      body: _loading
          ? const SizedBox.shrink()
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 40),
                        const SizedBox(height: 12),
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _loadUsers,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _users.isEmpty
                  ? const Center(child: Text('No family members yet.'))
                  : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    final usedStr = StorageBreakdown.formatBytes(user.storageUsedBytes);
                    final quotaStr = StorageBreakdown.formatBytes(user.storageQuotaBytes);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SpaceCard(
                        key: ValueKey('family-member-${user.id}'),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            MemberPortrait(
                              member: FamilyMember(user.id, user.name),
                              size: 48,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        user.name,
                                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: user.isAdmin
                                              ? const Color(0xFFE3F2FD)
                                              : const Color(0xFFF5F5F5),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: user.isAdmin
                                                ? const Color(0xFF1976D2)
                                                : style.muted,
                                          ),
                                        ),
                                        child: Text(
                                          user.isAdmin ? 'Admin' : 'Member',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: user.isAdmin
                                                ? const Color(0xFF1565C0)
                                                : const Color(0xFF424242),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    user.email,
                                    style: text.bodySmall?.copyWith(color: style.muted),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Storage: $usedStr of $quotaStr',
                                    style: text.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: style.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              key: ValueKey('delete-member-${user.id}'),
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                              tooltip: 'Remove user',
                              onPressed: () => _confirmDeleteUser(user),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _AddFamilyUserDialog extends StatefulWidget {
  const _AddFamilyUserDialog();

  @override
  State<_AddFamilyUserDialog> createState() => _AddFamilyUserDialogState();
}

class _AddFamilyUserDialogState extends State<_AddFamilyUserDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isAdmin = false;
  AvatarTone _selectedTone = AvatarTone.orange;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.person_add_rounded, color: Color(0xFF1A73E8)),
          SizedBox(width: 8),
          Text('Add Family Member', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Name'),
              const SizedBox(height: 4),
              TextFormField(
                key: const ValueKey('add-member-name'),
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  hintText: 'e.g. Papa, Maya',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Enter name' : null,
              ),
              const SizedBox(height: 12),
              const Text('Email'),
              const SizedBox(height: 4),
              TextFormField(
                key: const ValueKey('add-member-email'),
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'e.g. member@homespace.local',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || !v.contains('@') ? 'Enter valid email' : null,
              ),
              const SizedBox(height: 12),
              const Text('Password (min 8 chars)'),
              const SizedBox(height: 4),
              TextFormField(
                key: const ValueKey('add-member-password'),
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: '••••••••',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.length < 8 ? 'Min 8 characters' : null,
              ),
              const SizedBox(height: 12),
              const Text('Avatar Color'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final tone in AvatarTone.values)
                    ChoiceChip(
                      label: Text(tone.name),
                      selected: _selectedTone == tone,
                      onSelected: (_) => setState(() => _selectedTone = tone),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                key: const ValueKey('add-member-admin-switch'),
                title: const Text('Admin privileges', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Can manage family users and storage'),
                value: _isAdmin,
                onChanged: (val) => setState(() => _isAdmin = val),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('submit-add-member-btn'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              (
                name: _nameCtrl.text.trim(),
                email: _emailCtrl.text.trim(),
                password: _passCtrl.text,
                tone: _selectedTone,
                isAdmin: _isAdmin,
              ),
            );
          },
          child: const Text('Add Member'),
        ),
      ],
    );
  }
}
