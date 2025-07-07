import 'package:flutter/material.dart';

class CustomDateTimeField extends StatefulWidget {
  final String label;
  final String? errorText;
  final DateTime? selectedDate;
  final TimeOfDay? selectedTime;
  final VoidCallback? onDateTap;
  final VoidCallback? onTimeTap;
  final bool isRequired;
  final IconData icon;

  const CustomDateTimeField({
    super.key,
    required this.label,
    this.errorText,
    this.selectedDate,
    this.selectedTime,
    this.onDateTap,
    this.onTimeTap,
    this.isRequired = false,
    required this.icon,
  });

  @override
  State<CustomDateTimeField> createState() => _CustomDateTimeFieldState();
}

class _CustomDateTimeFieldState extends State<CustomDateTimeField> {
  bool _isFocused = false;

  bool get _hasContent =>
      widget.selectedDate != null || widget.selectedTime != null;
  bool get shouldFloatLabel => _isFocused || _hasContent;

  String get _displayText {
    if (widget.selectedDate != null && widget.selectedTime != null) {
      return '${widget.selectedDate!.year}/${widget.selectedDate!.month}/${widget.selectedDate!.day} ${widget.selectedTime!.format(context)}';
    } else if (widget.selectedDate != null) {
      return '${widget.selectedDate!.year}/${widget.selectedDate!.month}/${widget.selectedDate!.day}';
    } else if (widget.selectedTime != null) {
      return widget.selectedTime!.format(context);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _isFocused = true;
            });

            // 優先調用 onDateTap，如果沒有則調用 onTimeTap
            if (widget.onDateTap != null) {
              widget.onDateTap!.call();
            } else if (widget.onTimeTap != null) {
              widget.onTimeTap!.call();
            }

            // 延遲恢復焦點狀態
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted) {
                setState(() {
                  _isFocused = false;
                });
              }
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.errorText != null
                    ? Colors.red.withValues(alpha: 0.5)
                    : _isFocused
                    ? Colors.blue.withValues(alpha: 0.8)
                    : Colors.grey.withValues(alpha: 0.3),
                width: _isFocused ? 2.0 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              children: [
                // 浮動標籤
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  left: 16,
                  top: shouldFloatLabel ? 12 : 16,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: shouldFloatLabel ? 12 : 16,
                      color: widget.errorText != null
                          ? Colors.red
                          : _isFocused
                          ? Colors.blue
                          : Colors.grey.withValues(alpha: 0.7),
                      fontWeight: shouldFloatLabel
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.label),
                        if (widget.isRequired)
                          Text(
                            ' *',
                            style: TextStyle(
                              color: Colors.red.withValues(alpha: 0.8),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // 內容區域
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 48, // 為圖標留空間
                    top: shouldFloatLabel ? 32 : 16,
                    bottom: 16,
                  ),
                  child: Text(
                    _displayText,
                    style: TextStyle(
                      fontSize: 16,
                      color: _hasContent ? Colors.black87 : Colors.transparent,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),

                // 圖標
                Positioned(
                  right: 16,
                  top: shouldFloatLabel ? 28 : 19,
                  child: Icon(
                    widget.icon,
                    size: 20,
                    color: widget.errorText != null
                        ? Colors.red
                        : _isFocused
                        ? Colors.blue
                        : Colors.grey.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 底部錯誤提示
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 8),
            child: Text(
              widget.errorText!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }
}
