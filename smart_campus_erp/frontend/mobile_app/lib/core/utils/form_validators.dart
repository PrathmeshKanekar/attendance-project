import 'package:flutter/material.dart';

class FormValidators {
  FormValidators._();

  /// Generic required validator
  static String? required(String? value, [String? fieldName]) {
    if (value == null || value.trim().isEmpty) {
      return fieldName != null ? '$fieldName is required' : 'This field is required';
    }
    return null;
  }

  /// Email validator with strict regex
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$');
    if (!emailRegex.hasMatch(value.trim().toLowerCase())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  /// Phone validator (10-15 digits)
  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Phone number is required';
    final val = value.trim().replaceAll(' ', '').replaceAll('-', '');
    final phoneRegex = RegExp(r'^\+?\d{10,15}$');
    if (!phoneRegex.hasMatch(val)) {
      return 'Enter a valid 10-15 digit phone number';
    }
    return null;
  }

  /// Strict password validator
  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Password must be at least 8 characters';
    
    if (!value.contains(RegExp(r'[A-Z]'))) return 'Must contain at least one uppercase letter';
    if (!value.contains(RegExp(r'[a-z]'))) return 'Must contain at least one lowercase letter';
    if (!value.contains(RegExp(r'[0-9]'))) return 'Must contain at least one digit';
    if (!value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Must contain at least one special character';
    }
    return null;
  }

  /// Confirm password validator
  static String? confirmPassword(String? value, String originalPassword) {
    if (value != originalPassword) return 'Passwords do not match';
    return null;
  }

  /// Numeric range validator
  static String? range(num? value, double min, double max, [String? fieldName]) {
    if (value == null) return 'Value is required';
    if (value < min || value > max) {
      return '$fieldName must be between $min and $max';
    }
    return null;
  }

  /// Latitude validator
  static String? latitude(String? value) {
    if (value == null || value.isEmpty) return 'Latitude is required';
    final lat = double.tryParse(value);
    if (lat == null || lat < -90 || lat > 90) return 'Latitude must be -90 to 90';
    return null;
  }

  /// Longitude validator
  static String? longitude(String? value) {
    if (value == null || value.isEmpty) return 'Longitude is required';
    final lng = double.tryParse(value);
    if (lng == null || lng < -180 || lng > 180) return 'Longitude must be -180 to 180';
    return null;
  }

  /// Generic string length validator
  static String? minLength(String? value, int min, [String? fieldName]) {
    if (value == null || value.trim().length < min) {
      return fieldName != null 
          ? '$fieldName must be at least $min characters' 
          : 'At least $min characters required';
    }
    return null;
  }
}
