import 'package:flutter/material.dart';
import 'screens/auth_view.dart';
import 'screens/parent_view.dart';
import 'screens/player_view.dart';
import 'screens/group_view.dart';

class Routes {
  static Route<dynamic> generate(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const AuthView());
      case '/parent':
        return MaterialPageRoute(builder: (_) => const ParentView());
      case '/player':
        return MaterialPageRoute(builder: (_) => const PlayerView());
      case '/group':
        return MaterialPageRoute(builder: (_) => const GroupView());
      default:
        return MaterialPageRoute(builder: (_) => const AuthView());
    }
  }
}
