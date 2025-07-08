import 'package:flutter/material.dart';

class CustomDropdownField<T> extends StatefulWidget {
  final String label;
  final String? errorText;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final String? hintText;
  final bool isRequired;
  final IconData icon;
  final ValueChanged<T?>? onChanged;

  const CustomDropdownField({
    super.key,
    required this.label,
    this.errorText,
    this.value,
    required this.items,
    this.hintText,
    this.isRequired = false,
    this.icon = Icons.arrow_drop_down,
    this.onChanged,
  });

  @override
  State<CustomDropdownField<T>> createState() => _CustomDropdownFieldState<T>();
}

class _CustomDropdownFieldState<T> extends State<CustomDropdownField<T>> {
  bool _isFocused = false;

  bool get _hasContent => widget.value != null;
  bool get shouldFloatLabel => _isFocused || _hasContent;

  String get _displayText {
    if (widget.value != null) {
      // 找到對應的 item 並返回其文字
      final item = widget.items.firstWhere(
        (item) => item.value == widget.value,
        orElse: () => widget.items.first,
      );
      return item.child
          .toString()
          .replaceAll('Text("', '')
          .replaceAll('")', '');
    }
    return widget.hintText ?? '';
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
            _showDropdown();
          },
          child: Container(
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
                  left: 16,
                  top: shouldFloatLabel ? 12 : 16,
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
                      color: _hasContent
                          ? Colors.black87
                          : Colors.grey.withValues(alpha: 0.5),
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
                        ? Colors.black
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

  void _showDropdown() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 頂部把手
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 標題
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // 選項列表
              ...widget.items.map((item) {
                final isSelected = item.value == widget.value;
                return ListTile(
                  title: item.child,
                  trailing: isSelected
                      ? Icon(Icons.check, color: Colors.black)
                      : null,
                  onTap: () {
                    widget.onChanged?.call(item.value);
                    Navigator.pop(context);
                    setState(() {
                      _isFocused = false;
                    });
                  },
                );
              }).toList(),

              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        );
      },
    ).then((_) {
      setState(() {
        _isFocused = false;
      });
    });
  }
}
