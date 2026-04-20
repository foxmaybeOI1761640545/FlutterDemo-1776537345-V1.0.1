import "dart:async";

import "package:flutter/material.dart";

class RepeatActionIconButton extends StatefulWidget {
  const RepeatActionIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  State<RepeatActionIconButton> createState() => _RepeatActionIconButtonState();
}

class _RepeatActionIconButtonState extends State<RepeatActionIconButton> {
  Timer? _repeatTimer;

  void _startRepeating() {
    widget.onPressed();
    _repeatTimer?.cancel();
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      widget.onPressed();
    });
  }

  void _stopRepeating() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _stopRepeating();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _startRepeating(),
      onLongPressEnd: (_) => _stopRepeating(),
      onLongPressCancel: _stopRepeating,
      child: IconButton(
        tooltip: widget.tooltip,
        onPressed: widget.onPressed,
        icon: Icon(widget.icon),
      ),
    );
  }
}

class RepeatActionFilledButton extends StatefulWidget {
  const RepeatActionFilledButton({
    required this.onPressed,
    required this.child,
    this.tooltip,
    super.key,
  });

  final VoidCallback onPressed;
  final Widget child;
  final String? tooltip;

  @override
  State<RepeatActionFilledButton> createState() => _RepeatActionFilledButtonState();
}

class _RepeatActionFilledButtonState extends State<RepeatActionFilledButton> {
  Timer? _repeatTimer;

  void _startRepeating() {
    widget.onPressed();
    _repeatTimer?.cancel();
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      widget.onPressed();
    });
  }

  void _stopRepeating() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _stopRepeating();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget button = GestureDetector(
      onLongPressStart: (_) => _startRepeating(),
      onLongPressEnd: (_) => _stopRepeating(),
      onLongPressCancel: _stopRepeating,
      child: FilledButton.tonal(
        onPressed: widget.onPressed,
        child: widget.child,
      ),
    );

    final String? tooltip = widget.tooltip;
    if (tooltip == null || tooltip.isEmpty) {
      return button;
    }
    return Tooltip(message: tooltip, child: button);
  }
}
