class UserAccount {
  final String displayName;
  final String email;
  final String avatarUrl;
  final double storageUsedGB;
  final double storageTotalGB;
  final bool isBackupEnabled;
  final String backupStatusText;
  final bool isBackingUp;
  final bool isGuest;

  const UserAccount({
    required this.displayName,
    required this.email,
    required this.avatarUrl,
    required this.storageUsedGB,
    required this.storageTotalGB,
    this.isBackupEnabled = true,
    this.backupStatusText = 'Backup complete',
    this.isBackingUp = false,
    this.isGuest = false,
  });

  double get storagePercentage => (storageUsedGB / storageTotalGB).clamp(0.0, 1.0);

  UserAccount copyWith({
    String? displayName,
    String? email,
    String? avatarUrl,
    double? storageUsedGB,
    double? storageTotalGB,
    bool? isBackupEnabled,
    String? backupStatusText,
    bool? isBackingUp,
    bool? isGuest,
  }) {
    return UserAccount(
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      storageUsedGB: storageUsedGB ?? this.storageUsedGB,
      storageTotalGB: storageTotalGB ?? this.storageTotalGB,
      isBackupEnabled: isBackupEnabled ?? this.isBackupEnabled,
      backupStatusText: backupStatusText ?? this.backupStatusText,
      isBackingUp: isBackingUp ?? this.isBackingUp,
      isGuest: isGuest ?? this.isGuest,
    );
  }
}
