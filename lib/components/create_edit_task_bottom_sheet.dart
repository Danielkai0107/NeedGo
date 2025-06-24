import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

// 任務數據模型
class TaskData {
  String title;
  DateTime? date;
  TimeOfDay? time;
  String content;
  List<Uint8List> images; // 新上傳的圖片（bytes）
  List<String> existingImageUrls; // 已存在的圖片 URL
  int price;
  String? address;
  double? lat;
  double? lng;

  TaskData({
    this.title = '',
    this.date,
    this.time,
    this.content = '',
    List<Uint8List>? images,
    List<String>? existingImageUrls,
    this.price = 0,
    this.address,
    this.lat,
    this.lng,
  }) : images = images ?? [],
       existingImageUrls = existingImageUrls ?? [];

  // 從已有任務物件初始化
  TaskData.fromExisting(Map<String, dynamic> task)
    : title = task['title'] ?? task['name'] ?? '',
      date = task['date'] != null ? DateTime.parse(task['date']) : null,
      time = task['time'] != null
          ? TimeOfDay(
              hour: task['time']['hour'] ?? 0,
              minute: task['time']['minute'] ?? 0,
            )
          : null,
      content = task['content'] ?? '',
      images = [], // 新上傳的圖片
      existingImageUrls = task['images'] != null
          ? List<String>.from(task['images'])
          : [], // 從任務載入現有圖片 URL
      price = task['price'] ?? 0,
      address = task['address'],
      lat = task['lat']?.toDouble(),
      lng = task['lng']?.toDouble();

  // 取得總圖片數量
  int get totalImageCount => images.length + existingImageUrls.length;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'name': title, // 兼容現有字段
      'date': date?.toIso8601String(),
      'time': time != null
          ? {'hour': time!.hour, 'minute': time!.minute}
          : null,
      'content': content,
      'price': price,
      'address': address,
      'lat': lat,
      'lng': lng,
    };
  }
}

class CreateEditTaskBottomSheet extends StatefulWidget {
  // 新的 API（完整功能）
  final Map<String, dynamic>? existingTask;
  final Function(TaskData)? onSubmit;

  // 舊的 API（兼容現有代碼）
  final bool? isEditing;
  final Map<String, dynamic>? taskForm;
  final TextEditingController? nameController;
  final TextEditingController? contentController;
  final TextEditingController? locationSearchController;
  final List<Map<String, dynamic>>? locationSuggestions;
  final Function(String)? onLocationSearch;
  final Function(Map<String, dynamic>)? onLocationSelect;
  final VoidCallback? onSave;
  final VoidCallback? onCancel;

  const CreateEditTaskBottomSheet({
    super.key,
    // 新 API
    this.existingTask,
    this.onSubmit,
    // 舊 API（兼容）
    this.isEditing,
    this.taskForm,
    this.nameController,
    this.contentController,
    this.locationSearchController,
    this.locationSuggestions,
    this.onLocationSearch,
    this.onLocationSelect,
    this.onSave,
    this.onCancel,
  });

  @override
  State<CreateEditTaskBottomSheet> createState() =>
      _CreateEditTaskBottomSheetState();

  // 靜態方法顯示底部彈窗（新 API）
  static void show(
    BuildContext context, {
    Map<String, dynamic>? existingTask,
    required Function(TaskData) onSubmit,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => CreateEditTaskBottomSheet(
        existingTask: existingTask,
        onSubmit: onSubmit,
      ),
    );
  }
}

class _CreateEditTaskBottomSheetState extends State<CreateEditTaskBottomSheet>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animationController;

  // 確定是否使用舊 API
  bool get _isLegacyMode => widget.taskForm != null;

  int _currentStep = 0;
  final int _totalSteps = 6; // 從 5 改為 6

  // 表單數據
  late TaskData _taskData;

  // 表單控制器（內部使用）
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _addressController; // 新增地址控制器

  // UI 狀態
  bool _isSubmitting = false;
  final ImagePicker _imagePicker = ImagePicker();
  List<Map<String, dynamic>> _locationSuggestions = []; // 地址搜尋建議

  // 錯誤提示狀態
  String? _titleError;
  String? _dateError;
  String? _timeError;
  String? _contentError;
  String? _addressError; // 新增地址錯誤提示

  // Legacy API 相關
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _contentFocus = FocusNode();
  final FocusNode _locationFocus = FocusNode();

  @override
  void initState() {
    super.initState();

    if (_isLegacyMode) {
      // 兼容舊 API，不使用多步驟
      _initializeLegacyMode();
    } else {
      // 新的多步驟模式
      _initializeNewMode();
    }
  }

  void _initializeLegacyMode() {
    // 使用外部傳入的控制器
    _titleController = widget.nameController!;
    _contentController = widget.contentController!;

    // 從 taskForm 初始化數據
    _taskData = TaskData(
      title: widget.taskForm!['name'] ?? '',
      content: widget.taskForm!['content'] ?? '',
      address: widget.taskForm!['address'],
      lat: widget.taskForm!['lat']?.toDouble(),
      lng: widget.taskForm!['lng']?.toDouble(),
    );
  }

  void _initializeNewMode() {
    _pageController = PageController();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // 創建內部控制器
    _titleController = TextEditingController();
    _contentController = TextEditingController();
    _addressController = TextEditingController(); // 新增地址控制器

    // 初始化任務數據
    if (widget.existingTask != null) {
      _taskData = TaskData.fromExisting(widget.existingTask!);
      _titleController.text = _taskData.title;
      _contentController.text = _taskData.content;
      _addressController.text = _taskData.address ?? ''; // 初始化地址
    } else {
      _taskData = TaskData();
    }
  }

  @override
  void dispose() {
    if (!_isLegacyMode) {
      _pageController.dispose();
      _animationController.dispose();
      _titleController.dispose();
      _contentController.dispose();
      _addressController.dispose(); // 釋放地址控制器
    }
    _nameFocus.dispose();
    _contentFocus.dispose();
    _locationFocus.dispose();
    super.dispose();
  }

  // 清除錯誤提示
  void _clearErrors() {
    setState(() {
      _titleError = null;
      _dateError = null;
      _timeError = null;
      _contentError = null;
      _addressError = null; // 清除地址錯誤
    });
  }

  // 驗證當前步驟
  bool _validateCurrentStep() {
    _clearErrors();

    if (_isLegacyMode) return true;

    switch (_currentStep) {
      case 0: // 基礎資訊
        bool isValid = true;

        if (_taskData.title.isEmpty) {
          _titleError = '請輸入任務標題';
          isValid = false;
        }

        if (_taskData.date == null) {
          _dateError = '請選擇日期';
          isValid = false;
        }

        if (_taskData.time == null) {
          _timeError = '請選擇時間';
          isValid = false;
        }

        if (!isValid) {
          setState(() {}); // 觸發重繪顯示錯誤
        }

        return isValid;

      case 1: // 任務內容
        if (_taskData.content.isEmpty) {
          _contentError = '請輸入任務內容';
          setState(() {});
          return false;
        }
        return true;

      case 2: // 地址選擇
        if (_taskData.address == null || _taskData.address!.isEmpty) {
          _addressError = '請選擇任務地點';
          setState(() {});
          return false;
        }
        if (_taskData.lat == null || _taskData.lng == null) {
          _addressError = '請選擇有效的地點';
          setState(() {});
          return false;
        }
        return true;

      case 3: // 圖片上傳 (可選)
        return true;

      case 4: // 報價選項
        return true;

      case 5: // 預覽
        return true;

      default:
        return false;
    }
  }

  // 下一步
  void _nextStep() {
    if (_validateCurrentStep() && _currentStep < _totalSteps - 1) {
      setState(() {
        _currentStep++;
      });
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _animationController.forward();
    } else {
      // 顯示錯誤提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請完成必填項目'), backgroundColor: Colors.red),
      );
    }
  }

  // 上一步
  void _previousStep() {
    if (_currentStep > 0) {
      _clearErrors(); // 返回上一步時清除錯誤
      setState(() {
        _currentStep--;
      });
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  // 提交表單
  void _submitForm() async {
    if (!_validateCurrentStep()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請檢查所有必填項目'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      if (_isLegacyMode) {
        // 舊 API - 直接調用 onSave
        widget.onSave?.call();
      } else {
        // 新 API - 更新任務數據並調用回調
        _taskData.title = _titleController.text;
        _taskData.content = _contentController.text;

        widget.onSubmit?.call(_taskData);

        // 不在這裡執行 pop，由外部處理
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失敗: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLegacyMode) {
      return _buildLegacyView();
    } else {
      return _buildNewView();
    }
  }

  // 兼容舊版本的視圖
  Widget _buildLegacyView() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputSection(
            title: '任務名稱',
            icon: Icons.assignment,
            child: TextField(
              controller: widget.nameController,
              focusNode: _nameFocus,
              decoration: InputDecoration(
                hintText: '請輸入任務名稱',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue[500]!, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (v) => widget.taskForm!['name'] = v,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _contentFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 20),
          _buildInputSection(
            title: '任務內容',
            icon: Icons.description,
            child: TextField(
              controller: widget.contentController,
              focusNode: _contentFocus,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '請詳細描述任務內容...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue[500]!, width: 2),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
              onChanged: (v) => widget.taskForm!['content'] = v,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _locationFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 20),
          _buildInputSection(
            title: '任務地點',
            icon: Icons.location_on,
            child: Column(
              children: [
                TextField(
                  controller: widget.locationSearchController,
                  focusNode: _locationFocus,
                  decoration: InputDecoration(
                    hintText: '搜尋地點...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.blue[500]!,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (value) {
                    widget.onLocationSearch?.call(value);
                  },
                  textInputAction: TextInputAction.search,
                ),
                if (widget.locationSuggestions!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.locationSuggestions!.length,
                      itemBuilder: (context, index) {
                        final place = widget.locationSuggestions![index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            Icons.location_on,
                            color: Colors.grey[600],
                            size: 20,
                          ),
                          title: Text(
                            place['description'],
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () => widget.onLocationSelect?.call(place),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: widget.onCancel,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: const Text(
                    '取消',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: widget.onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    widget.isEditing! ? '儲存修改' : '創建任務',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  // 新版本的多步驟視圖
  Widget _buildNewView() {
    return DraggableScrollableSheet(
      initialChildSize: 0.75, // 降低初始高度從 0.85 到 0.75
      minChildSize: 0.4, // 降低最小高度從 0.5 到 0.4
      maxChildSize: 0.85, // 降低最大高度從 0.95 到 0.85
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              spreadRadius: 0,
              offset: Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          children: [
            // 拖拽指示器
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 標題欄
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.close),
                  ),
                  Expanded(
                    child: Text(
                      widget.existingTask != null ? '編輯任務' : '新增任務',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48), // 平衡關閉按鈕
                ],
              ),
            ),

            // 步驟內容
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep1BasicInfo(),
                  _buildStep2TaskContent(),
                  _buildStep3AddressSelection(), // 新增地址選擇步驟
                  _buildStep4ImageUpload(), // 原來的步驟3變成步驟4
                  _buildStep5PriceOption(), // 原來的步驟4變成步驟5
                  _buildStep6Preview(), // 原來的步驟5變成步驟6
                ],
              ),
            ),

            // 進度條 + 控制欄
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.1),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 進度條移到這裡
                  _buildProgressBar(),
                  const SizedBox(height: 16),
                  // 控制按鈕
                  _buildControlBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  // 進度條
  Widget _buildProgressBar() {
    return Row(
      children: List.generate(_totalSteps, (index) {
        final isCompleted = index < _currentStep;
        final isCurrent = index == _currentStep;

        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: index < _totalSteps - 1 ? 8 : 0),
            decoration: BoxDecoration(
              color: isCompleted || isCurrent ? Colors.blue : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  // 控制欄
  Widget _buildControlBar() {
    return Row(
      children: [
        // 上一步按鈕
        if (_currentStep > 0)
          Expanded(
            child: OutlinedButton(
              onPressed: _previousStep,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.blue),
              ),
              child: const Text('上一步'),
            ),
          ),

        if (_currentStep > 0) const SizedBox(width: 16),

        // 下一步/提交按鈕
        Expanded(
          child: ElevatedButton(
            onPressed: _isSubmitting
                ? null
                : (_currentStep == _totalSteps - 1 ? _submitForm : _nextStep),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              disabledBackgroundColor: Colors.grey[300],
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(_currentStep == _totalSteps - 1 ? '送出' : '下一步'),
          ),
        ),
      ],
    );
  }

  // 步驟1：基礎資訊
  Widget _buildStep1BasicInfo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '步驟 1/5: 基礎資訊',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // 任務標題
          const Text('任務標題 *', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              hintText: '請輸入任務標題',
              border: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _titleError != null ? Colors.red : Colors.grey,
                ),
              ),
              errorBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.red),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 16,
              ),
              errorText: _titleError,
            ),
            onChanged: (value) {
              setState(() {
                _taskData.title = value;
                if (value.isNotEmpty) _titleError = null; // 清除錯誤
              });
            },
          ),

          const SizedBox(height: 24),

          // 日期選擇
          const Text('日期 *', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _selectDate(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _dateError != null ? Colors.red : Colors.grey,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _taskData.date != null
                        ? '${_taskData.date!.year}/${_taskData.date!.month}/${_taskData.date!.day}'
                        : '選擇日期',
                    style: TextStyle(
                      color: _taskData.date != null
                          ? Colors.black
                          : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_dateError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 12),
              child: Text(
                _dateError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),

          const SizedBox(height: 24),

          // 時間選擇
          const Text('時間 *', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _selectTime(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _timeError != null ? Colors.red : Colors.grey,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    _taskData.time != null
                        ? _taskData.time!.format(context)
                        : '選擇時間',
                    style: TextStyle(
                      color: _taskData.time != null
                          ? Colors.black
                          : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_timeError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 12),
              child: Text(
                _timeError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  // 步驟2：任務內容
  Widget _buildStep2TaskContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '步驟 2/5: 任務內容',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          const Text('任務描述 *', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: _contentController,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: '請詳細描述您的任務內容...',
              border: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _contentError != null ? Colors.red : Colors.grey,
                ),
              ),
              errorBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.red),
              ),
              contentPadding: const EdgeInsets.all(12),
              errorText: _contentError,
            ),
            onChanged: (value) {
              setState(() {
                _taskData.content = value;
                if (value.isNotEmpty) _contentError = null; // 清除錯誤
              });
            },
          ),
        ],
      ),
    );
  }

  // 步驟3：地址選擇
  Widget _buildStep3AddressSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '步驟 3/6: 地址選擇',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          const Text('任務地點 *', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: _addressController,
            decoration: InputDecoration(
              hintText: '搜尋地點...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _addressError != null ? Colors.red : Colors.grey,
                ),
              ),
              errorBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.red),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 16,
              ),
              errorText: _addressError,
            ),
            onChanged: (value) {
              if (value.isNotEmpty) {
                _searchLocations(value);
                if (_addressError != null) {
                  setState(() {
                    _addressError = null; // 清除錯誤
                  });
                }
              } else {
                setState(() {
                  _locationSuggestions = [];
                });
              }
            },
          ),

          // 地點建議列表
          if (_locationSuggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _locationSuggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _locationSuggestions[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.location_on,
                      color: Colors.grey[600],
                      size: 20,
                    ),
                    title: Text(
                      suggestion['description'],
                      style: const TextStyle(fontSize: 14),
                    ),
                    onTap: () => _selectLocation(suggestion),
                  );
                },
              ),
            ),
          ],

          // 顯示已選擇的地址
          if (_taskData.address != null && _taskData.address!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已選擇: ${_taskData.address}',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 步驟4：圖片上傳
  Widget _buildStep4ImageUpload() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '步驟 4/6: 圖片上傳',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '最多可上傳 3 張圖片，每張檔案大小限制 2 MB',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          const SizedBox(height: 24),

          // 圖片網格
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: 3,
            itemBuilder: (context, index) {
              final existingImageCount = _taskData.existingImageUrls.length;
              final newImageCount = _taskData.images.length;
              final totalImageCount = existingImageCount + newImageCount;

              if (index < totalImageCount) {
                if (index < existingImageCount) {
                  // 顯示現有圖片（從 URL）
                  return Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _taskData.existingImageUrls[index],
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey[200],
                                child: Icon(
                                  Icons.image_not_supported,
                                  color: Colors.grey[400],
                                  size: 40,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeExistingImage(index),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                } else {
                  // 顯示新上傳的圖片（從 bytes）
                  final newImageIndex = index - existingImageCount;
                  return Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _taskData.images[newImageIndex],
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeNewImage(newImageIndex),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
              } else {
                // 顯示添加按鈕
                return GestureDetector(
                  onTap: totalImageCount < 3 ? _pickImage : null,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: totalImageCount < 3
                            ? Colors.blue
                            : Colors.grey[300]!,
                        style: BorderStyle.solid,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate,
                          size: 32,
                          color: totalImageCount < 3
                              ? Colors.blue
                              : Colors.grey[400],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '添加圖片',
                          style: TextStyle(
                            fontSize: 12,
                            color: totalImageCount < 3
                                ? Colors.blue
                                : Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // 步驟5：報價選項
  Widget _buildStep5PriceOption() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '步驟 5/6: 報價選項',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          const Text('任務報酬', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(
            '設定您願意支付的報酬金額（以 100 為單位）',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
          const SizedBox(height: 16),

          // 報酬滑桿
          Column(
            children: [
              Text(
                _taskData.price == 0 ? '免費' : 'NT\$ ${_taskData.price}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 16),
              Slider(
                value: _taskData.price.toDouble(),
                min: 0,
                max: 1000,
                divisions: 10,
                label: _taskData.price == 0 ? '免費' : 'NT\$ ${_taskData.price}',
                onChanged: (value) {
                  setState(() {
                    _taskData.price = value.round();
                  });
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('免費', style: TextStyle(color: Colors.grey[600])),
                  Text('NT\$ 1000', style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 快速選擇按鈕
          const Text('快速選擇', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [0, 100, 200, 300, 500, 1000].map((price) {
              final isSelected = _taskData.price == price;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _taskData.price = price;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue : Colors.white,
                    border: Border.all(
                      color: isSelected ? Colors.blue : Colors.grey[300]!,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    price == 0 ? '免費' : 'NT\$ $price',
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: isSelected
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // 步驟6：預覽與送出
  Widget _buildStep6Preview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '步驟 6/6: 預覽與送出',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // 預覽卡片
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 標題
                  Text(
                    _taskData.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 日期時間
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        _taskData.date != null && _taskData.time != null
                            ? '${_taskData.date!.year}/${_taskData.date!.month}/${_taskData.date!.day} ${_taskData.time!.format(context)}'
                            : '未設定時間',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // 內容
                  const Text(
                    '任務內容',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _taskData.content,
                    style: TextStyle(color: Colors.grey[700]),
                  ),

                  const SizedBox(height: 12),

                  // 圖片
                  if (_taskData.totalImageCount > 0) ...[
                    const Text(
                      '任務圖片',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 80,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _taskData.totalImageCount,
                        itemBuilder: (context, index) {
                          return Container(
                            margin: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: index < _taskData.existingImageUrls.length
                                  ? Image.network(
                                      _taskData.existingImageUrls[index],
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                      loadingBuilder:
                                          (context, child, loadingProgress) {
                                            if (loadingProgress == null)
                                              return child;
                                            return const SizedBox(
                                              width: 80,
                                              height: 80,
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            );
                                          },
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Container(
                                              width: 80,
                                              height: 80,
                                              color: Colors.grey[200],
                                              child: Icon(
                                                Icons.image_not_supported,
                                                color: Colors.grey[400],
                                              ),
                                            );
                                          },
                                    )
                                  : Image.memory(
                                      _taskData.images[index -
                                          _taskData.existingImageUrls.length],
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 報酬
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.monetization_on, color: Colors.green[600]),
                        const SizedBox(width: 8),
                        Text(
                          '報酬: ${_taskData.price == 0 ? '免費' : 'NT\$ ${_taskData.price}'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 選擇日期
  void _selectDate() async {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final dayAfterTomorrow = now.add(const Duration(days: 2)); // 增加後天

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _taskData.date ?? now,
      firstDate: now,
      lastDate: dayAfterTomorrow, // 改為後天
      selectableDayPredicate: (date) {
        // 可以選擇今天、明天、後天
        return date.day == now.day ||
            date.day == tomorrow.day ||
            date.day == dayAfterTomorrow.day;
      },
    );

    if (selectedDate != null) {
      setState(() {
        _taskData.date = selectedDate;
        if (_dateError != null) _dateError = null; // 清除錯誤
      });
    }
  }

  // 選擇時間
  void _selectTime() async {
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: _taskData.time ?? TimeOfDay.now(),
    );

    if (selectedTime != null) {
      setState(() {
        _taskData.time = selectedTime;
        if (_timeError != null) _timeError = null; // 清除錯誤
      });
    }
  }

  // 選擇圖片 - 改進版本，直接自動裁切
  void _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();

        // 檢查檔案大小（2MB限制）
        if (bytes.length > 2 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('圖片檔案大小不能超過 2MB'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        // 直接自動裁切為正方形並添加到列表
        await _autoCropAndAddImage(bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('選擇圖片失敗: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 自動裁切圖片為正方形
  Future<void> _autoCropAndAddImage(Uint8List imageBytes) async {
    try {
      // 解碼圖片
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      // 計算正方形裁切區域
      final size = math.min(image.width, image.height);
      final offsetX = (image.width - size) / 2;
      final offsetY = (image.height - size) / 2;

      // 創建畫布並裁切
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final srcRect = Rect.fromLTWH(
        offsetX.toDouble(),
        offsetY.toDouble(),
        size.toDouble(),
        size.toDouble(),
      );
      final destRect = const Rect.fromLTWH(0, 0, 300, 300); // 300x300 正方形

      canvas.drawImageRect(image, srcRect, destRect, Paint());

      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(300, 300);
      final byteData = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null && mounted) {
        setState(() {
          _taskData.images.add(byteData.buffer.asUint8List());
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('圖片已自動裁切並添加'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('圖片處理失敗: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 移除現有圖片（URL）
  void _removeExistingImage(int index) {
    setState(() {
      _taskData.existingImageUrls.removeAt(index);
    });
  }

  // 移除新上傳的圖片（bytes）
  void _removeNewImage(int index) {
    setState(() {
      _taskData.images.removeAt(index);
    });
  }

  // 搜尋地點（使用 Google Places API）
  Future<void> _searchLocations(String query) async {
    if (query.isEmpty) {
      setState(() {
        _locationSuggestions = [];
      });
      return;
    }

    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

    if (apiKey.isEmpty) {
      // 如果沒有 API Key，使用台北真實地點作為模擬數據
      _setMockLocationSuggestions(query);
      return;
    }

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(query)}'
        '&key=$apiKey'
        '&language=zh-TW&components=country:tw',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List;
          final suggestions = <Map<String, dynamic>>[];

          for (var prediction in predictions.take(5)) {
            // 限制最多5個建議
            // 取得地點詳細資訊（包含座標）
            final placeDetails = await _getPlaceDetails(
              prediction['place_id'],
              apiKey,
            );
            if (placeDetails != null) {
              suggestions.add({
                'description': prediction['description'],
                'place_id': prediction['place_id'],
                'lat': placeDetails['lat'],
                'lng': placeDetails['lng'],
              });
            }
          }

          if (mounted) {
            setState(() {
              _locationSuggestions = suggestions;
            });
          }
        } else {
          print('Google Places API 錯誤: ${data['status']}');
          _setMockLocationSuggestions(query);
        }
      } else {
        print('HTTP 錯誤: ${response.statusCode}');
        _setMockLocationSuggestions(query);
      }
    } catch (e) {
      print('搜尋地點失敗: $e');
      _setMockLocationSuggestions(query);
    }
  }

  // 設定模擬地點建議（台北真實地點）
  void _setMockLocationSuggestions(String query) {
    if (!mounted) return;

    final mockLocations = [
      {
        'description': '台北101, 台北市信義區',
        'place_id': 'mock_101',
        'lat': 25.0340,
        'lng': 121.5645,
      },
      {
        'description': '台北車站, 台北市中正區',
        'place_id': 'mock_station',
        'lat': 25.0478,
        'lng': 121.5170,
      },
      {
        'description': '西門町, 台北市萬華區',
        'place_id': 'mock_ximending',
        'lat': 25.0424,
        'lng': 121.5062,
      },
      {
        'description': '士林夜市, 台北市士林區',
        'place_id': 'mock_shilin',
        'lat': 25.0879,
        'lng': 121.5240,
      },
      {
        'description': '大安森林公園, 台北市大安區',
        'place_id': 'mock_daan_park',
        'lat': 25.0329,
        'lng': 121.5354,
      },
    ];

    // 根據搜尋關鍵字過濾結果
    final filteredLocations = mockLocations.where((location) {
      final description = location['description'] as String;
      return description.toLowerCase().contains(query.toLowerCase());
    }).toList();

    setState(() {
      _locationSuggestions = filteredLocations.isNotEmpty
          ? filteredLocations
          : mockLocations;
    });
  }

  // 取得地點詳細資訊（包含座標）
  Future<Map<String, double>?> _getPlaceDetails(
    String placeId,
    String apiKey,
  ) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=$placeId&key=$apiKey&fields=geometry',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'OK') {
          final location = data['result']['geometry']['location'];
          return {
            'lat': location['lat'].toDouble(),
            'lng': location['lng'].toDouble(),
          };
        }
      }
    } catch (e) {
      print('取得地點詳情失敗: $e');
    }

    return null;
  }

  // 選擇地點
  void _selectLocation(Map<String, dynamic> place) {
    setState(() {
      _taskData.address = place['description'];
      _taskData.lat = place['lat']?.toDouble();
      _taskData.lng = place['lng']?.toDouble();
      _addressController.text = place['description'];
      _locationSuggestions = []; // 清空建議列表
      if (_addressError != null) _addressError = null; // 清除錯誤
    });
  }
}
