import 'package:flutter/material.dart';

class CustomTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String? hintText;
  final String? errorText;
  final int? maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Function(String)? onChanged;
  final VoidCallback? onTap;
  final Function(String)? onSubmitted;
  final bool readOnly;
  final bool isRequired;

  const CustomTextField({
    super.key,
    required this.controller,
    this.focusNode,
    required this.label,
    this.hintText,
    this.errorText,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onTap,
    this.onSubmitted,
    this.readOnly = false,
    this.isRequired = false,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChanged);
    }
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  bool get _hasContent => widget.controller.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final bool shouldFloatLabel = _isFocused || _hasContent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.errorText != null
                  ? Colors.red.withValues(alpha: 0.5)
                  : _isFocused
                  ? Colors.black.withValues(alpha: 0.8)
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
                left: shouldFloatLabel ? 16 : 20,
                top: shouldFloatLabel ? 8 : 16,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: shouldFloatLabel ? 12 : 16,
                    color: widget.errorText != null
                        ? Colors.red
                        : _isFocused
                        ? Colors.black
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

              // 輸入框
              TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                maxLines: widget.maxLines,
                maxLength: widget.maxLength,
                keyboardType: widget.keyboardType,
                textInputAction: widget.textInputAction,
                readOnly: widget.readOnly,
                onChanged: (value) {
                  setState(() {}); // 觸發重建以更新浮動標籤
                  widget.onChanged?.call(value);
                },
                onTap: widget.onTap,
                onSubmitted: widget.onSubmitted,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                  fontWeight: FontWeight.w400,
                ),
                decoration: InputDecoration(
                  hintText: shouldFloatLabel ? widget.hintText : null,
                  hintStyle: TextStyle(
                    color: Colors.grey.withValues(alpha: 0.5),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: shouldFloatLabel ? 32 : 16,
                    bottom: 16,
                  ),
                  counterText: '', // 隱藏默認計數器
                ),
              ),
            ],
          ),
        ),
        // 底部信息區域
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 錯誤提示
              if (widget.errorText != null)
                Expanded(
                  child: Text(
                    widget.errorText!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),

              // 字數統計
              if (widget.maxLength != null)
                Text(
                  '${widget.controller.text.length} 個字 ( 最多 ${widget.maxLength} 個字 )',
                  style: TextStyle(
                    color: Colors.grey.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
