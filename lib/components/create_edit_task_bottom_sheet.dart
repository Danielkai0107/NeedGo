import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/custom_snackbar.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/custom_date_time_field.dart';

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
      useSafeArea: true, // 使用安全區域
      builder: (context) => CreateEditTaskBottomSheet(
        existingTask: existingTask,
        onSubmit: onSubmit,
      ),
    );
  }
}

class _CreateEditTaskBottomSheetState extends State<CreateEditTaskBottomSheet>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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

  // 專用的 FocusNode
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _contentFocusNode = FocusNode();
  final FocusNode _addressFocusNode = FocusNode();

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
  String? _imageError; // 新增圖片錯誤提示

  // Legacy API 相關
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _contentFocus = FocusNode();
  final FocusNode _locationFocus = FocusNode();

  // 鍵盤狀態追蹤
  double _lastKeyboardHeight = 0.0;

  @override
  void initState() {
    super.initState();

    // 添加鍵盤監聽器
    WidgetsBinding.instance.addObserver(this);

    // 初始化鍵盤高度
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _lastKeyboardHeight = MediaQuery.of(context).viewInsets.bottom;
      }
    });

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
    // 移除鍵盤監聽器
    WidgetsBinding.instance.removeObserver(this);

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

    // 釋放新增的 FocusNode
    _titleFocusNode.dispose();
    _contentFocusNode.dispose();
    _addressFocusNode.dispose();

    super.dispose();
  }

  /// 監聽鍵盤狀態變化
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    if (!mounted) return;

    final currentKeyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    // 檢測鍵盤是否收起
    // 當鍵盤高度從有值變為 0 或明顯減少時，取消焦點
    if (_lastKeyboardHeight > 50 && currentKeyboardHeight < 50) {
      // 鍵盤收起了，取消所有輸入框的焦點
      FocusScope.of(context).unfocus();
      print('🎹 檢測到鍵盤收起，自動取消輸入框焦點');
    }

    // 更新記錄的鍵盤高度
    _lastKeyboardHeight = currentKeyboardHeight;
  }

  // 清除錯誤提示
  void _clearErrors() {
    setState(() {
      _titleError = null;
      _dateError = null;
      _timeError = null;
      _contentError = null;
      _addressError = null; // 清除地址錯誤
      _imageError = null; // 清除圖片錯誤
    });
  }

  // 檢查時間是否有效（不能是過去時間或未來5分鐘內）
  bool _isTimeValid(DateTime date, TimeOfDay time) {
    final now = DateTime.now();
    final selectedDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    // 檢查是否是過去的時間
    if (selectedDateTime.isBefore(now)) {
      return false;
    }

    // 檢查是否是未來5分鐘內的時間
    final fiveMinutesLater = now.add(const Duration(minutes: 5));
    if (selectedDateTime.isBefore(fiveMinutesLater)) {
      return false;
    }

    return true;
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

        // 檢查時間有效性
        if (_taskData.date != null && _taskData.time != null) {
          if (!_isTimeValid(_taskData.date!, _taskData.time!)) {
            final now = DateTime.now();
            final selectedDateTime = DateTime(
              _taskData.date!.year,
              _taskData.date!.month,
              _taskData.date!.day,
              _taskData.time!.hour,
              _taskData.time!.minute,
            );

            if (selectedDateTime.isBefore(now)) {
              _timeError = '不能選擇過去的時間';
            } else {
              _timeError = '請選擇至少5分鐘後的時間';
            }
            isValid = false;
          }
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
    }
    // 不需要 SnackBar 錯誤提示，因為輸入框已經有錯誤提示
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
      // 不需要 SnackBar 錯誤提示，因為輸入框已經有錯誤提示
      return;
    }

    if (mounted) {
      setState(() {
        _isSubmitting = true;
      });
    }

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
      // 不使用 SnackBar，避免當機，改為 print 調試
      print('提交失敗: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
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
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 100, // 固定底部間距，避免鍵盤衝突
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputSection(
            title: '任務名稱',
            icon: Icons.assignment,
            child: CustomTextField(
              controller: widget.nameController!,
              focusNode: _nameFocus,
              label: '任務名稱',
              maxLength: 40,
              textInputAction: TextInputAction.next,
              onChanged: (v) => widget.taskForm!['name'] = v,
              onSubmitted: (_) => _contentFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 20),
          _buildInputSection(
            title: '任務內容',
            icon: Icons.description,
            child: CustomTextField(
              controller: widget.contentController!,
              focusNode: _contentFocus,
              label: '任務內容',
              hintText: '請詳細描述任務內容...',
              maxLines: 3,
              maxLength: 200,
              textInputAction: TextInputAction.next,
              onChanged: (v) => widget.taskForm!['content'] = v,
              onSubmitted: (_) => _locationFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 20),
          _buildInputSection(
            title: '任務地點',
            icon: Icons.location_on,
            child: Column(
              children: [
                CustomTextField(
                  controller: widget.locationSearchController!,
                  focusNode: _locationFocus,
                  label: '任務地點',
                  hintText: '搜尋地點...',
                  textInputAction: TextInputAction.search,
                  onChanged: (value) {
                    widget.onLocationSearch?.call(value);
                  },
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
      initialChildSize: 0.8, // 調整初始高度
      minChildSize: 0.5, // 調整最小高度
      maxChildSize: 0.95, // 調整最大高度，給鍵盤留更多空間
      expand: false, // 不強制展開
      snap: true, // 啟用吸附
      snapSizes: const [0.5, 0.8, 0.95], // 設置吸附點
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
        child: GestureDetector(
          onTap: () {
            // 點擊空白處關閉鍵盤
            FocusScope.of(context).unfocus();
          },
          child: Column(
            children: [
              // 拖拽指示器
              GestureDetector(
                onTap: () {
                  // 點擊拖拽指示器也關閉鍵盤
                  FocusScope.of(context).unfocus();
                },
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 標題欄
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        // 先關閉鍵盤
                        FocusScope.of(context).unfocus();
                        // 延遲一下再關閉彈窗
                        Future.delayed(const Duration(milliseconds: 100), () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
                    Expanded(
                      child: Text(
                        widget.existingTask != null ? '編輯任務' : '新增任務',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48), // 平衡關閉按鈕
                  ],
                ),
              ),

              // 步驟內容 - 使用 NotificationListener 處理滾動衝突
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification notification) {
                    // 當內部有滾動時，阻止外部 DraggableScrollableSheet 處理滾動
                    return false;
                  },
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
              ),

              // 進度條 + 控制欄
              Container(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(context).padding.bottom,
                ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0, // 文字左右內部間距
                  vertical: 16, // 文字上下內部間距
                ),
                textStyle: const TextStyle(
                  fontSize: 15, // 按鈕文字大小
                  fontWeight: FontWeight.w600, // (選)字重
                ),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0, // 文字左右內部間距
                vertical: 16, // 文字上下內部間距
              ),
              disabledBackgroundColor: Colors.grey[300],
              textStyle: const TextStyle(
                fontSize: 15, // 按鈕文字大小
                fontWeight: FontWeight.w600, // (選)字重
              ),
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
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 120, // 為控制欄留固定空間，避免鍵盤衝突
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '首先，請填寫基礎資訊',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          CustomTextField(
            controller: _titleController,
            focusNode: _titleFocusNode,
            label: '任務標題',
            isRequired: true,
            errorText: _titleError,
            maxLength: 40,
            textInputAction: TextInputAction.next,
            onChanged: (value) {
              setState(() {
                _taskData.title = value;
                if (value.isNotEmpty) _titleError = null; // 清除錯誤
              });
            },
          ),

          const SizedBox(height: 24),

          CustomDateTimeField(
            label: '日期',
            isRequired: true,
            icon: Icons.calendar_today,
            selectedDate: _taskData.date,
            errorText: _dateError,
            onDateTap: _selectDate,
          ),

          const SizedBox(height: 24),

          CustomDateTimeField(
            label: '時間',
            isRequired: true,
            icon: Icons.access_time,
            selectedTime: _taskData.time,
            errorText: _timeError,
            onTimeTap: _selectTime,
          ),
        ],
      ),
    );
  }

  // 步驟2：任務內容
  Widget _buildStep2TaskContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 120, // 為控制欄留固定空間，避免鍵盤衝突
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '步驟 2/6: 任務內容',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          CustomTextField(
            controller: _contentController,
            focusNode: _contentFocusNode,
            label: '任務描述',
            isRequired: true,
            hintText: '請詳細描述您的任務內容...',
            errorText: _contentError,
            maxLines: 8,
            maxLength: 200,
            textInputAction: TextInputAction.newline,
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
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 120, // 為控制欄留固定空間，避免鍵盤衝突
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '步驟 3/6: 地址選擇',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          CustomTextField(
            controller: _addressController,
            focusNode: _addressFocusNode,
            label: '任務地點',
            isRequired: true,
            hintText: '搜尋地點...',
            errorText: _addressError,
            textInputAction: TextInputAction.search,
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
                        fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 120, // 為控制欄留固定空間，避免鍵盤衝突
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '步驟 4/6: 圖片上傳',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '最多可上傳 3 張圖片，系統會自動壓縮以節省空間',
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
                            fit: BoxFit.contain,
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

          // 顯示圖片錯誤提示
          if (_imageError != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[600], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _imageError!,
                      style: TextStyle(
                        color: Colors.red[700],
                        fontSize: 14,
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

  // 步驟5：報價選項
  Widget _buildStep5PriceOption() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 120, // 為控制欄留固定空間，避免鍵盤衝突
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '步驟 5/6: 報價選項',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          const Text('任務報酬', style: TextStyle(fontWeight: FontWeight.w600)),
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
          const Text('快速選擇', style: TextStyle(fontWeight: FontWeight.w600)),
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
                          ? FontWeight.w600
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
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 120, // 為控制欄留固定空間，避免鍵盤衝突
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                    style: TextStyle(fontWeight: FontWeight.w600),
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
                      style: TextStyle(fontWeight: FontWeight.w600),
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
                                      fit: BoxFit.contain,
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
                            fontWeight: FontWeight.w600,
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
    // 先清除所有輸入框的焦點，防止選擇完成後重新獲得焦點
    FocusScope.of(context).unfocus();

    // 延遲一下確保焦點清除完成
    await Future.delayed(const Duration(milliseconds: 100));

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

    if (selectedDate != null && mounted) {
      setState(() {
        _taskData.date = selectedDate;
        _dateError = null; // 清除日期錯誤

        // 重新檢查已選擇的時間是否仍然有效
        if (_taskData.time != null) {
          if (!_isTimeValid(selectedDate, _taskData.time!)) {
            final now = DateTime.now();
            final selectedDateTime = DateTime(
              selectedDate.year,
              selectedDate.month,
              selectedDate.day,
              _taskData.time!.hour,
              _taskData.time!.minute,
            );

            if (selectedDateTime.isBefore(now)) {
              _timeError = '不能選擇過去的時間';
            } else {
              _timeError = '請選擇至少5分鐘後的時間';
            }
          } else {
            _timeError = null; // 時間有效，清除錯誤
          }
        }
      });

      // 延遲確保 setState 完成後再清除焦點，防止重建時重新獲得焦點
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) {
        FocusScope.of(context).unfocus();
        // 明確清除所有相關的 FocusNode
        _titleFocusNode.unfocus();
        _contentFocusNode.unfocus();
        _addressFocusNode.unfocus();
      }
    }
  }

  // 選擇時間 - 改為滾動選擇器
  void _selectTime() async {
    // 先清除所有輸入框的焦點，防止選擇完成後重新獲得焦點
    FocusScope.of(context).unfocus();

    // 延遲一下確保焦點清除完成
    await Future.delayed(const Duration(milliseconds: 100));

    final selectedTime = await _showScrollTimePickerDialog();

    if (selectedTime != null && mounted) {
      setState(() {
        _taskData.time = selectedTime;

        // 即時檢查時間有效性
        if (_taskData.date != null) {
          if (!_isTimeValid(_taskData.date!, selectedTime)) {
            final now = DateTime.now();
            final selectedDateTime = DateTime(
              _taskData.date!.year,
              _taskData.date!.month,
              _taskData.date!.day,
              selectedTime.hour,
              selectedTime.minute,
            );

            if (selectedDateTime.isBefore(now)) {
              _timeError = '不能選擇過去的時間';
            } else {
              _timeError = '請選擇至少5分鐘後的時間';
            }
          } else {
            _timeError = null; // 清除錯誤
          }
        } else {
          _timeError = null; // 如果還沒選日期，清除時間錯誤
        }
      });

      // 延遲確保 setState 完成後再清除焦點，防止重建時重新獲得焦點
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) {
        FocusScope.of(context).unfocus();
        // 明確清除所有相關的 FocusNode
        _titleFocusNode.unfocus();
        _contentFocusNode.unfocus();
        _addressFocusNode.unfocus();
      }
    }
  }

  // 滾動時間選擇器對話框
  Future<TimeOfDay?> _showScrollTimePickerDialog() async {
    final now = TimeOfDay.now();
    final currentTime = _taskData.time ?? now;

    int selectedHour = currentTime.hour;
    int selectedMinute = currentTime.minute;

    return showDialog<TimeOfDay>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            '選擇時間',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              return SizedBox(
                height: 200,
                width: 300,
                child: Row(
                  children: [
                    // 小時選擇器
                    Expanded(
                      child: Column(
                        children: [
                          const Text(
                            '時',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListWheelScrollView.useDelegate(
                              itemExtent: 40,
                              perspective: 0.005,
                              diameterRatio: 1.2,
                              physics: const FixedExtentScrollPhysics(),
                              controller: FixedExtentScrollController(
                                initialItem: selectedHour,
                              ),
                              onSelectedItemChanged: (index) {
                                setDialogState(() {
                                  selectedHour = index;
                                });
                              },
                              childDelegate: ListWheelChildBuilderDelegate(
                                builder: (context, index) {
                                  if (index < 0 || index > 23) return null;
                                  return Container(
                                    alignment: Alignment.center,
                                    child: Text(
                                      index.toString().padLeft(2, '0'),
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: selectedHour == index
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: selectedHour == index
                                            ? Colors.blue
                                            : Colors.black,
                                      ),
                                    ),
                                  );
                                },
                                childCount: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 分隔符
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const Text(
                        ':',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // 分鐘選擇器
                    Expanded(
                      child: Column(
                        children: [
                          const Text(
                            '分',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListWheelScrollView.useDelegate(
                              itemExtent: 40,
                              perspective: 0.005,
                              diameterRatio: 1.2,
                              physics: const FixedExtentScrollPhysics(),
                              controller: FixedExtentScrollController(
                                initialItem: selectedMinute ~/ 5, // 5分鐘間隔
                              ),
                              onSelectedItemChanged: (index) {
                                setDialogState(() {
                                  selectedMinute = index * 5; // 5分鐘間隔
                                });
                              },
                              childDelegate: ListWheelChildBuilderDelegate(
                                builder: (context, index) {
                                  if (index < 0 || index > 11)
                                    return null; // 0, 5, 10, ..., 55
                                  final minute = index * 5;
                                  return Container(
                                    alignment: Alignment.center,
                                    child: Text(
                                      minute.toString().padLeft(2, '0'),
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: selectedMinute == minute
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: selectedMinute == minute
                                            ? Colors.blue
                                            : Colors.black,
                                      ),
                                    ),
                                  );
                                },
                                childCount: 12, // 0-55分，每5分鐘一個間隔
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 取消
              },
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final selectedTime = TimeOfDay(
                  hour: selectedHour,
                  minute: selectedMinute,
                );
                Navigator.of(context).pop(selectedTime);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('確認'),
            ),
          ],
        );
      },
    );
  }

  // 選擇圖片 - 改進版本，直接自動壓縮
  void _pickImage() async {
    // 開始選擇圖片時清除之前的錯誤
    if (mounted) {
      setState(() {
        _imageError = null;
      });
    }

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();

        // 直接自動壓縮圖片（保持原圖比例），無大小限制
        await _autoCropAndCompressImage(bytes);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _imageError = '選擇圖片失敗，請重試';
        });
      }
      print('選擇圖片失敗: $e');
    }
  }

  // 自動壓縮圖片（保持原圖比例）
  Future<void> _autoCropAndCompressImage(Uint8List imageBytes) async {
    try {
      // 解碼圖片
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      // 計算等比例縮放尺寸，最大邊不超過 400 像素
      final maxSize = 400;
      double newWidth, newHeight;

      if (image.width > image.height) {
        // 寬圖：以寬度為基準
        newWidth = maxSize.toDouble();
        newHeight = (image.height * maxSize) / image.width;
      } else {
        // 高圖或正方形：以高度為基準
        newHeight = maxSize.toDouble();
        newWidth = (image.width * maxSize) / image.height;
      }

      // 創建畫布並等比例縮放
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // 使用整個原圖，不裁切
      final srcRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final destRect = Rect.fromLTWH(0, 0, newWidth, newHeight);

      canvas.drawImageRect(image, srcRect, destRect, Paint());

      final picture = recorder.endRecording();
      final compressedImage = await picture.toImage(
        newWidth.round(),
        newHeight.round(),
      );
      final byteData = await compressedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null && mounted) {
        final compressedBytes = byteData.buffer.asUint8List();
        final originalSize = imageBytes.length;
        final compressedSize = compressedBytes.length;

        print(
          '圖片壓縮完成: ${(originalSize / 1024 / 1024).toStringAsFixed(1)}MB -> ${(compressedSize / 1024).toStringAsFixed(1)}KB (${newWidth.round()}x${newHeight.round()})',
        );

        setState(() {
          _taskData.images.add(compressedBytes);
          _imageError = null; // 成功時清除錯誤
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _imageError = '圖片處理失敗，請重試';
        });
      }
      print('圖片處理失敗: $e');
    }
  }

  // 移除現有圖片（URL）
  void _removeExistingImage(int index) {
    if (mounted) {
      setState(() {
        _taskData.existingImageUrls.removeAt(index);
        _imageError = null; // 移除圖片時清除錯誤
      });
    }
  }

  // 移除新上傳的圖片（bytes）
  void _removeNewImage(int index) {
    if (mounted) {
      setState(() {
        _taskData.images.removeAt(index);
        _imageError = null; // 移除圖片時清除錯誤
      });
    }
  }

  // 搜尋地點（使用 Google Places API）
  Future<void> _searchLocations(String query) async {
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _locationSuggestions = [];
        });
      }
      return;
    }

    // 詳細調試 dotenv 載入狀態
    print('🔍 調試 dotenv 狀態:');
    print('   - dotenv.env 鍵數量: ${dotenv.env.length}');
    print('   - 所有環境變數鍵: ${dotenv.env.keys.toList()}');

    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

    // 調試：檢查 API key 是否正確讀取
    print(
      '🔑 Google Maps API Key 狀態: ${apiKey.isEmpty ? "未設定或為空" : "已設定 (${apiKey.length} 字符)"}',
    );
    if (apiKey.isNotEmpty) {
      print(
        '🔑 API Key 前10字符: ${apiKey.length > 10 ? apiKey.substring(0, 10) + "..." : apiKey}',
      );
    }

    if (apiKey.isEmpty) {
      print('⚠️ 使用模擬數據，因為 API Key 未設定');
      print('💡 請檢查：');
      print('   1. .env 文件是否在專案根目錄');
      print('   2. pubspec.yaml 是否包含 assets: [.env]');
      print('   3. main.dart 是否調用了 dotenv.load()');
      print('   4. .env 文件格式：GOOGLE_MAPS_API_KEY=你的金鑰');
      // 如果沒有 API Key，使用模擬數據
      _setMockLocationSuggestions(query);
      return;
    }

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(query)}'
        '&key=$apiKey'
        '&language=zh-TW'
        '&components=country:tw'
        '&types=establishment|geocode',
      );

      print('🌐 發送 API 請求: ${url.toString().replaceAll(apiKey, '[API_KEY]')}');
      final response = await http.get(url);
      print('📡 API 回應狀態: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('📊 API 回應狀態: ${data['status']}');

        if (data['status'] == 'OK') {
          final predictions = data['predictions'] as List;
          print('🎯 找到 ${predictions.length} 個地點建議');

          final suggestions = <Map<String, dynamic>>[];

          // 只獲取基本信息，不在搜尋階段獲取座標
          for (var prediction in predictions.take(5)) {
            suggestions.add({
              'description': prediction['description'],
              'place_id': prediction['place_id'],
              // 暫時不設置座標，在選擇時才獲取
              'lat': null,
              'lng': null,
            });
          }

          if (mounted) {
            setState(() {
              _locationSuggestions = suggestions;
            });
          }
        } else {
          print('❌ Google Places API 錯誤: ${data['status']}');
          if (data['error_message'] != null) {
            print('📝 錯誤詳情: ${data['error_message']}');
          }
          _setMockLocationSuggestions(query);
        }
      } else {
        print('❌ HTTP 錯誤: ${response.statusCode}');
        print('📝 回應內容: ${response.body}');
        _setMockLocationSuggestions(query);
      }
    } catch (e) {
      print('❌ 搜尋地點異常: $e');
      _setMockLocationSuggestions(query);
    }
  }

  // 設定模擬地點建議（台灣地點）
  void _setMockLocationSuggestions(String query) {
    if (!mounted) return;

    final mockLocations = [
      {
        'description': '台北101, 台北市信義區, 台灣',
        'place_id': 'mock_101',
        'lat': 25.0340,
        'lng': 121.5645,
      },
      {
        'description': '台北車站, 台北市中正區, 台灣',
        'place_id': 'mock_station',
        'lat': 25.0478,
        'lng': 121.5170,
      },
      {
        'description': '西門町, 台北市萬華區, 台灣',
        'place_id': 'mock_ximending',
        'lat': 25.0424,
        'lng': 121.5062,
      },
      {
        'description': '士林夜市, 台北市士林區, 台灣',
        'place_id': 'mock_shilin',
        'lat': 25.0879,
        'lng': 121.5240,
      },
      {
        'description': '大安森林公園, 台北市大安區, 台灣',
        'place_id': 'mock_daan_park',
        'lat': 25.0329,
        'lng': 121.5354,
      },
      {
        'description': '淡水老街, 新北市淡水區, 台灣',
        'place_id': 'mock_tamsui',
        'lat': 25.1677,
        'lng': 121.4413,
      },
      {
        'description': '九份老街, 新北市瑞芳區, 台灣',
        'place_id': 'mock_jiufen',
        'lat': 25.1092,
        'lng': 121.8419,
      },
      {
        'description': '中正紀念堂, 台北市中正區, 台灣',
        'place_id': 'mock_cks',
        'lat': 25.0360,
        'lng': 121.5200,
      },
    ];

    // 根據搜尋關鍵字過濾結果，限制最多5個
    final filteredLocations = mockLocations
        .where((location) {
          final description = location['description'] as String;
          return description.toLowerCase().contains(query.toLowerCase());
        })
        .take(5)
        .toList();

    if (mounted) {
      setState(() {
        _locationSuggestions = filteredLocations.isNotEmpty
            ? filteredLocations
            : mockLocations.take(5).toList();
      });
    }
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
  void _selectLocation(Map<String, dynamic> place) async {
    if (mounted) {
      setState(() {
        _taskData.address = place['description'];
        _addressController.text = place['description'];
        _locationSuggestions = []; // 清空建議列表
        if (_addressError != null) _addressError = null; // 清除錯誤
      });

      // 如果是模擬數據，直接使用已有的座標
      if (place['lat'] != null && place['lng'] != null) {
        setState(() {
          _taskData.lat = place['lat']?.toDouble();
          _taskData.lng = place['lng']?.toDouble();
        });
      } else {
        // 如果是 Google API 結果，現在才獲取座標
        final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
        if (apiKey.isNotEmpty && place['place_id'] != null) {
          final placeDetails = await _getPlaceDetails(
            place['place_id'],
            apiKey,
          );
          if (placeDetails != null && mounted) {
            setState(() {
              _taskData.lat = placeDetails['lat'];
              _taskData.lng = placeDetails['lng'];
            });
          }
        }
      }

      // 延遲確保 setState 完成後再清除焦點，防止重建時重新獲得焦點
      await Future.delayed(const Duration(milliseconds: 150));
      if (mounted) {
        FocusScope.of(context).unfocus();
        // 明確清除所有相關的 FocusNode
        _titleFocusNode.unfocus();
        _contentFocusNode.unfocus();
        _addressFocusNode.unfocus();
      }
    }
  }
}
