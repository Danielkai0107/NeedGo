// lib/routes.dart

import 'package:flutter/material.dart';
import 'screens/auth_gate.dart';
import 'screens/auth_view.dart';
import 'screens/registration_view.dart';
import 'screens/player_view.dart';
import 'screens/parent_view.dart';
import 'screens/chat_list_screen.dart';

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
      case '/player':
        return MaterialPageRoute(builder: (_) => const PlayerView());
      case '/parent':
        return MaterialPageRoute(builder: (_) => const ParentView());
      case '/chat':
        return MaterialPageRoute(builder: (_) => const ChatListScreen());
      default:
        return MaterialPageRoute(builder: (_) => const AuthView());
    }
  }
}
