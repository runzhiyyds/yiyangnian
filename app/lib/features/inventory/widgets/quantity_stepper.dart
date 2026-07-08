import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 数量控件：支持 +1/-1 和手动输入，数量 >= 0
class QuantityStepper extends StatefulWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.enabled = true,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final bool enabled;

  @override
  State<QuantityStepper> createState() => _QuantityStepperState();
}

class _QuantityStepperState extends State<QuantityStepper> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _syncFromController();
    }
  }

  @override
  void didUpdateWidget(QuantityStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncFromController() {
    final text = _controller.text.trim();
    var v = int.tryParse(text);
    if (v == null || v < widget.min) {
      v = widget.min;
    }
    _controller.text = v.toString();
    if (v != widget.value) {
      widget.onChanged(v);
    }
  }

  void _increment() {
    final v = (widget.value + 1).clamp(widget.min, 999999);
    _controller.text = v.toString();
    widget.onChanged(v);
  }

  void _decrement() {
    final v = (widget.value - 1).clamp(widget.min, 999999);
    _controller.text = v.toString();
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: widget.enabled && widget.value > widget.min ? _decrement : null,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
        SizedBox(
          width: 64,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _syncFromController(),
            onTapOutside: (_) => _syncFromController(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: widget.enabled ? _increment : null,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}
