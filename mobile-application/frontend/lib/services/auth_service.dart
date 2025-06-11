import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _usernameKey = 'username';
  static const String _passwordKey = 'password';

  static Future<void> saveCredentials(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey, username);
    await prefs.setString(_passwordKey, password);
  }

  static Future<Map<String, String>?> getStoredCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_usernameKey);
    final password = prefs.getString(_passwordKey);
    
    if (username != null && password != null) {
      return {
        'username': username,
        'password': password,
      };
    }
    return null;
  }

  static Future<void> clearStoredCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_usernameKey);
    await prefs.remove(_passwordKey);
  }
}
