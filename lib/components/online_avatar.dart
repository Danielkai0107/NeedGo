import 'package:flutter/material.dart';
import '../services/chat_service.dart';

/// 帶在線狀態指示器的頭像組件
class OnlineAvatar extends StatelessWidget {
  final String userId;
  final String? avatarUrl;
  final double radius;
  final bool showOnlineStatus;
  final double? onlineIndicatorSize;

  const OnlineAvatar({
    Key? key,
    required this.userId,
    this.avatarUrl,
    required this.radius,
    this.showOnlineStatus = true,
    this.onlineIndicatorSize,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final indicatorSize = onlineIndicatorSize ?? (radius * 0.4);

    return Stack(
      children: [
        // 頭像
        Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            shape: BoxShape.circle,
          ),
          child: avatarUrl?.isNotEmpty == true
              ? ClipOval(
                  child: Image.network(
                    avatarUrl!,
                    width: radius * 2,
                    height: radius * 2,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.person,
                        color: Colors.grey[600],
                        size: radius,
                      );
                    },
                  ),
                )
              : Icon(Icons.person, color: Colors.grey[600], size: radius),
        ),

        // 在線狀態指示器
        if (showOnlineStatus)
          Positioned(
            bottom: 0,
            right: 0,
            child: StreamBuilder<bool>(
              stream: ChatService.getUserOnlineStatus(userId),
              builder: (context, snapshot) {
                final isOnline = snapshot.data ?? false;

                return Container(
                  width: indicatorSize,
                  height: indicatorSize,
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// 簡化的在線狀態頭像（用於訊息氣泡）
class SimpleOnlineAvatar extends StatelessWidget {
  final String userId;
  final String? avatarUrl;
  final double size;
  final bool showOnlineStatus;

  const SimpleOnlineAvatar({
    Key? key,
    required this.userId,
    this.avatarUrl,
    required this.size,
    this.showOnlineStatus = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 頭像
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            shape: BoxShape.circle,
          ),
          child: avatarUrl?.isNotEmpty == true
              ? ClipOval(
                  child: Image.network(
                    avatarUrl!,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.person,
                        color: Colors.grey[600],
                        size: size * 0.6,
                      );
                    },
                  ),
                )
              : Icon(Icons.person, color: Colors.grey[600], size: size * 0.6),
        ),

        // 在線狀態指示器（較小）
        if (showOnlineStatus)
          Positioned(
            bottom: 0,
            right: 0,
            child: StreamBuilder<bool>(
              stream: ChatService.getUserOnlineStatus(userId),
              builder: (context, snapshot) {
                final isOnline = snapshot.data ?? false;

                return Container(
                  width: size * 0.3,
                  height: size * 0.3,
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
