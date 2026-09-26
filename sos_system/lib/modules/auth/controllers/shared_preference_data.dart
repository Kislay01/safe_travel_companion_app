import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferenceData {
  String name = "";
  String email = "";
  String role = "";
  String uid = "";
  String mobile = "";
  bool isUserLoggedIn = false;

  //SET DATA
  Future<void> setSharedPreferenceData(Map<String, dynamic> obj) async {
    SharedPreferences sharedPreferencesObj = await SharedPreferences.getInstance();

    await sharedPreferencesObj.setString('name', obj['name'] ?? "");
    await sharedPreferencesObj.setString('email', obj['email'] ?? "");
    await sharedPreferencesObj.setString('role', obj['role'] ?? "");
    await sharedPreferencesObj.setString('uid', obj['uid'] ?? "");
    await sharedPreferencesObj.setString('mobile', obj['mobile'] ?? "");
    await sharedPreferencesObj.setBool('isUserLoggedIn', obj['loginFlag'] ?? false);
  }

  //GET DATA
  Future<void> getSharedPreferenceData() async {
    SharedPreferences sharedPreferenceObj = await SharedPreferences.getInstance();

    name = sharedPreferenceObj.getString('name') ?? "";
    email = sharedPreferenceObj.getString('email') ?? "";
    role = sharedPreferenceObj.getString('role') ?? "";
    uid = sharedPreferenceObj.getString('uid') ?? "";
    mobile = sharedPreferenceObj.getString('mobile') ?? "";
    isUserLoggedIn = sharedPreferenceObj.getBool('isUserLoggedIn') ?? false;
  }
}
