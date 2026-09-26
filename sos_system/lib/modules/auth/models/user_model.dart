class UserModel {
  String uid;
  String name;
  String email;
  String mobile;
  String role;
  String password; // newly added

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.mobile,
    required this.role,
    required this.password,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'mobile': mobile,
      'role': role,
      'password': password,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      mobile: map['mobile'] ?? '',
      role: map['role'] ?? '',
      password: map['password'] ?? '',
    );
  }
}
