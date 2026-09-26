import 'package:flutter/material.dart';

class SlideToConfirm extends StatefulWidget {
  final Function(String) onConfirm;
  final String? preview;

  /// 未持有控制权时禁用滑动，防止下发出后端会拒绝的切台指令。
  final bool enabled;

  const SlideToConfirm({
    super.key,
    required this.onConfirm,
    this.preview,
    this.enabled = true,
  });

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm>
    with SingleTickerProviderStateMixin {
  double _dragPosition = 0;
  bool _isDragging = false;
  late AnimationController _resetController;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _resetSlider() {
    _resetController.forward(from: 0).then((_) {
      setState(() => _dragPosition = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final caption = !enabled
        ? '未持有控制权'
        : (widget.preview == null || widget.preview!.isEmpty
            ? '>>> 先选一个机位 >>>'
            : '>>> 滑动以确认切台 >>>');

    return Column(
      children: [
        // 预览提示
        if (widget.preview != null && widget.preview!.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade800,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '即将切台: ${widget.preview}',
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),

        // 滑动条
        LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            return GestureDetector(
              onHorizontalDragStart: enabled
                  ? (details) => setState(() => _isDragging = true)
                  : null,
              onHorizontalDragUpdate: enabled
                  ? (details) => setState(() {
                        _dragPosition = (_dragPosition + details.delta.dx)
                            .clamp(0.0, maxWidth - 60);
                      })
                  : null,
              onHorizontalDragEnd: enabled
                  ? (details) {
                      setState(() => _isDragging = false);
                      final preview = widget.preview;
                      if (_dragPosition > maxWidth * 0.7 && preview != null && preview.isNotEmpty) {
                        // 滑动超过 70% 触发；没有选中机位时不触发，避免下发空指令。
                        widget.onConfirm(preview);
                      }
                      _resetSlider();
                    }
                  : null,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: enabled ? Colors.grey.shade700 : Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Stack(
                  children: [
                    // 背景文字
                    Center(
                      child: Text(
                        caption,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: _isDragging ? 0.3 : 0.6),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // 滑块
                    Positioned(
                      left: _dragPosition,
                      top: 4,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: !enabled
                              ? Colors.grey.shade600
                              : (_dragPosition > maxWidth * 0.5 ? Colors.green : Colors.blue),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
