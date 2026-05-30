class SavedAccount {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String provider;
  final DateTime addedAt;
  final bool isActive;

  const SavedAccount({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.provider,
    required this.addedAt,
    this.isActive = false,
  });

  SavedAccount copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    String? provider,
    DateTime? addedAt,
    bool? isActive,
  }) {
    return SavedAccount(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      provider: provider ?? this.provider,
      addedAt: addedAt ?? this.addedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'provider': provider,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'isActive': isActive,
  };

  factory SavedAccount.fromMap(Map<String, dynamic> map) => SavedAccount(
    uid: map['uid'] as String,
    email: map['email'] as String,
    displayName: map['displayName'] as String,
    photoUrl: map['photoUrl'] as String?,
    provider: map['provider'] as String,
    addedAt: DateTime.fromMillisecondsSinceEpoch(map['addedAt'] as int),
    isActive: map['isActive'] as bool? ?? false,
  );
}
