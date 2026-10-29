class UserModel {
  final int? id;
  final String? supabaseUserId;
  final String name;
  final String email;
  final String passwordHash;
  final String role;
  final String status;
  final String? bio;
  final String? phone;
  final String? location;
  final String? profileImagePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserModel({
    this.id,
    this.supabaseUserId,
    required this.name,
    required this.email,
    required this.passwordHash,
    this.role = 'user',
    this.status = 'active',
    this.bio,
    this.phone,
    this.location,
    this.profileImagePath,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supabase_user_id': supabaseUserId,
      'name': name,
      'email': email,
      'password_hash': passwordHash,
      'role': role,
      'status': status,
      'bio': bio,
      'phone': phone,
      'location': location,
      'profile_image_path': profileImagePath,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as int?,
      supabaseUserId: map['supabase_user_id'] as String?,
      name: map['name'] as String,
      email: map['email'] as String,
      passwordHash: map['password_hash'] as String,
      role: map['role'] as String? ?? 'user',
      status: map['status'] as String? ?? 'active',
      bio: map['bio'] as String?,
      phone: map['phone'] as String?,
      location: map['location'] as String?,
      profileImagePath: map['profile_image_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isActive => status == 'active';
}
