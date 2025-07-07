// lib/routes.dart

import 'package:flutter/material.dart';
import 'screens/auth_gate.dart';
import 'screens/auth_view.dart';
import 'screens/registration_view.dart';
import 'screens/unified_map_view.dart';
import 'screens/chat_list_screen.dart';
import 'screens/main_tab_view.dart';

class Routes {
  static Route<dynamic> generate(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const AuthGate());
      case '/auth':
        return MaterialPageRoute(builder: (_) => const AuthView());
      case '/registration':
        final args = settings.arguments as Map<String, String>;
        return MaterialPageRoute(
          builder: (_) => RegistrationView(
            uid: args['uid']!,
            phoneNumber: args['phoneNumber']!,
          ),
        );
      case '/map':
        return MaterialPageRoute(builder: (_) => const UnifiedMapView());
      case '/main':
        return MaterialPageRoute(builder: (_) => const MainTabView());
      case '/chat':
        return MaterialPageRoute(builder: (_) => const ChatListScreen());
      default:
        return MaterialPageRoute(builder: (_) => const AuthView());
    }
  }
}
