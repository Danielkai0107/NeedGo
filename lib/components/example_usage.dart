import 'package:flutter/material.dart';
import 'create_edit_task_bottom_sheet.dart';

class TaskCreationExample extends StatefulWidget {
  @override
  _TaskCreationExampleState createState() => _TaskCreationExampleState();
}

class _TaskCreationExampleState extends State<TaskCreationExample> {
  List<TaskData> _tasks = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('任務管理範例'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 控制按鈕區域
          Container(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showCreateTaskSheet(),
                    icon: Icon(Icons.add),
                    label: Text('新增任務'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 任務列表
          Expanded(
            child: _tasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.task_alt, size: 64, color: Colors.grey[400]),
                        SizedBox(height: 16),
                        Text(
                          '還沒有任務',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '點擊上方按鈕來新增第一個任務',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: _tasks.length,
                    itemBuilder: (context, index) {
                      final task = _tasks[index];
                      return _buildTaskCard(task, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // 任務卡片
  Widget _buildTaskCard(TaskData task, int index) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showEditTaskSheet(task, index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 標題和價格
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: task.price == 0
                          ? Colors.green[100]
                          : Colors.blue[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      task.price == 0 ? '免費' : 'NT\$ ${task.price}',
                      style: TextStyle(
                        color: task.price == 0
                            ? Colors.green[700]
                            : Colors.blue[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 12),

              // 日期時間
              if (task.date != null && task.time != null)
                Row(
                  children: [
                    Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                    SizedBox(width: 8),
                    Text(
                      '${task.date!.year}/${task.date!.month}/${task.date!.day} ${task.time!.format(context)}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),

              SizedBox(height: 8),

              // 內容
              Text(
                task.content,
                style: TextStyle(color: Colors.grey[700], height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // 圖片
              if (task.images.isNotEmpty) ...[
                SizedBox(height: 12),
                SizedBox(
                  height: 60,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: task.images.length,
                    itemBuilder: (context, imgIndex) {
                      return Container(
                        margin: EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            task.images[imgIndex],
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],

              SizedBox(height: 12),

              // 操作按鈕
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _showEditTaskSheet(task, index),
                    icon: Icon(Icons.edit, size: 16),
                    label: Text('編輯'),
                    style: TextButton.styleFrom(foregroundColor: Colors.blue),
                  ),
                  SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _deleteTask(index),
                    icon: Icon(Icons.delete, size: 16),
                    label: Text('刪除'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 顯示新增任務底部彈窗
  void _showCreateTaskSheet() {
    CreateEditTaskBottomSheet.show(
      context,
      onSubmit: (taskData) {
        setState(() {
          _tasks.add(taskData);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('任務「${taskData.title}」新增成功！'),
            backgroundColor: Colors.green,
          ),
        );
      },
    );
  }

  // 顯示編輯任務底部彈窗
  void _showEditTaskSheet(TaskData existingTask, int index) {
    CreateEditTaskBottomSheet.show(
      context,
      existingTask: existingTask.toJson(),
      onSubmit: (taskData) {
        setState(() {
          _tasks[index] = taskData;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('任務「${taskData.title}」更新成功！'),
            backgroundColor: Colors.blue,
          ),
        );
      },
    );
  }

  // 刪除任務
  void _deleteTask(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('確認刪除'),
        content: Text('確定要刪除任務「${_tasks[index].title}」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _tasks.removeAt(index);
              });
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('任務已刪除'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            child: Text('刪除'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }
}
