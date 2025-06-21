// lib/screen/demo.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GroupView extends StatefulWidget {
  const GroupView({Key? key}) : super(key: key);

  @override
  State<GroupView> createState() => _GroupViewState();
}

class _GroupViewState extends State<GroupView> {
  // 當前 sheet 拖動高度比例，範圍 0.0 ~ 1.0
  double _sheetExtent = 0.3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar 延伸至畫面頂端
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Draggable Sheet Demo'),
        // 當拖到全屏時，背景顏色改為白色，文字改為黑色
        backgroundColor:
            _sheetExtent >= 1.0 ? Colors.white : Colors.transparent,
        elevation: 0,
        foregroundColor:
            _sheetExtent >= 1.0 ? Colors.black : Colors.white,
        systemOverlayStyle: _sheetExtent >= 1.0
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
      ),
      body: Stack(
        children: [
          // 背景圖或其他主要內容
          Positioned.fill(
            child: Image.network(
              'https://picsum.photos/800/1200',
              fit: BoxFit.cover,
            ),
          ),

          // 監聽 DraggableScrollableSheet 的拖曳進度
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (notification) {
              setState(() {
                _sheetExtent = notification.extent;
              });
              return true;
            },
            child: DraggableScrollableSheet(
              // 初始高度佔父容器的 30%
              initialChildSize: 0.3,
              // 最小高度佔 20%
              minChildSize: 0.2,
              // 最多可以滑到全屏
              maxChildSize: 1.0,
              // 啟用吸附效果，並設定三階段快照位置
              snap: true,
              snapSizes: const [0.5, 0.66, 1.0],
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: 30,
                    itemBuilder: (context, index) {
                      return ListTile(
                        leading: const Icon(Icons.task),
                        title: Text('範例項目 ${index + 1}'),
                        subtitle: const Text('這是示範用的列表內容'),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
