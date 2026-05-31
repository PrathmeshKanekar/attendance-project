class UserModel {
  final String  id;
  final String  email;
  final String  firstName;
  final String  lastName;
  final String  fullName;
  final String  role;
  final String? phone;
  final String? profilePhoto;
  final String? collegeId;
  final String? collegeName;
  final String? collegeCode;
  final String? prn;
  final String? deviceId;
  final bool    isApproved;
  final bool    isActive;
  final List<Map<String, dynamic>> departments;

  const UserModel({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.role,
    this.phone,
    this.profilePhoto,
    this.collegeId,
    this.collegeName,
    this.collegeCode,
    this.prn,
    this.deviceId,
    required this.isApproved,
    required this.isActive,
    this.departments = const [],
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    var deptsList = <Map<String, dynamic>>[];
    if (json['departments'] != null && json['departments'] is List) {
      deptsList = (json['departments'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return UserModel(
      id           : json['id']?.toString() ?? '',
      email        : json['email']?.toString() ?? '',
      firstName    : json['first_name']?.toString() ?? '',
      lastName     : json['last_name']?.toString() ?? '',
      fullName     : json['full_name']?.toString() ?? '',
      role         : json['role']?.toString() ?? 'student',
      phone        : json['phone']?.toString(),
      profilePhoto : json['profile_photo']?.toString(),
      collegeId    : json['college_id']?.toString(),
      collegeName  : json['college_name']?.toString(),
      collegeCode  : json['college_code']?.toString(),
      prn          : json['prn']?.toString(),
      deviceId     : json['device_id']?.toString(),
      isApproved   : json['is_approved'] == true,
      isActive     : json['is_active'] == true,
      departments  : deptsList,
    );
  }

  Map<String, dynamic> toJson() => {
    'id'           : id,
    'email'        : email,
    'first_name'   : firstName,
    'last_name'    : lastName,
    'full_name'    : fullName,
    'role'         : role,
    'phone'        : phone,
    'profile_photo': profilePhoto,
    'college_id'   : collegeId,
    'college_name' : collegeName,
    'college_code' : collegeCode,
    'prn'          : prn,
    'device_id'    : deviceId,
    'is_approved'  : isApproved,
    'is_active'    : isActive,
    'departments'  : departments,
  };

  bool get isStudent      => role == 'student';
  bool get isTeacher      => role == 'teacher';
  bool get isPrincipal    => role == 'principal';
  bool get isHOD          => role == 'hod';
  bool get isCollegeAdmin => role == 'college_admin';
  bool get isSuperAdmin   => role == 'super_admin';
  bool get isLabAssistant => role == 'lab_assistant';

  String get initials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty  ? lastName[0]  : '';
    return '$f$l'.toUpperCase();
  }
}
