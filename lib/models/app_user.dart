class AppUser {
  final String uid;
  final String displayName;

  const AppUser({required this.uid, required this.displayName});

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
          ? (data['displayName'] as String).trim()
          : 'Pengguna',
    );
  }
}
