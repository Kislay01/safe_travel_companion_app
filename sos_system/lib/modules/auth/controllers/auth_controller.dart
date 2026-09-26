import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sos_system/modules/auth/models/user_model.dart';

class AuthController {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  FirebaseAuth get firebaseAuth => _firebaseAuth;
  FirebaseFirestore get firestore => _firestore;

  /// SIGN UP — Stores user under "Child" or "Guardian" collection
  /// Uses email as document ID, does NOT store password in Firestore
  Future<String?> signUp(UserModel user, String password) async {
    try {
      // Firebase Authentication signup
      UserCredential userCredential =
          await _firebaseAuth.createUserWithEmailAndPassword(
        email: user.email,
        password: password,
      );

      user.uid = userCredential.user!.uid;

      // Remove password from user data
      final data = user.toMap();
      data.remove('password');

      // Save user data in role collection using email as doc ID
      await _firestore.collection(user.role).doc(user.email).set(data);

      return null; // Success
    } on FirebaseAuthException catch (e) {
      return e.message;
    } on FirebaseException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// LOGIN — Validates using FirebaseAuth, checks role in Firestore
  Future<String?> login(String email, String password, String selectedRole) async {
    try {
      // Firebase Authentication login
      await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Fetch user data from Firestore by email
      DocumentSnapshot doc =
          await _firestore.collection(selectedRole).doc(email).get();

      if (!doc.exists) return "User not found in $selectedRole records.";

      final roleInDB = (doc.data() as Map<String, dynamic>)['role'] ?? "Child";
      if (roleInDB != selectedRole) {
        return "Selected role does not match our records.";
      }

      return null; // Login successful
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// OPTIONAL: Get user data by role & email
  Future<Map<String, dynamic>?> getUserData(String email, String role) async {
    try {
      DocumentSnapshot doc = await _firestore.collection(role).doc(email).get();
      if (!doc.exists) return null;
      return doc.data() as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
}
