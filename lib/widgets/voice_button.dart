import 'package:flutter/material.dart';

class VoiceButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isListening;
  final bool isEnabled;

  const VoiceButton({
    super.key,
    required this.onPressed,
    required this.isListening,
    required this.isEnabled,
  });

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    if (widget.isListening) {
      _animationController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(VoiceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !oldWidget.isListening) {
      _animationController.repeat(reverse: true);
    } else if (!widget.isListening && oldWidget.isListening) {
      _animationController.stop();
      _animationController.reset();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isListening ? _scaleAnimation.value : 1.0,
          child: IconButton(
            onPressed: widget.isEnabled ? widget.onPressed : null,
            icon: Icon(
              widget.isListening ? Icons.mic : Icons.mic_none,
            ),
            tooltip: widget.isListening ? 'Listening...' : 'Voice Input',
            style: IconButton.styleFrom(
              backgroundColor: widget.isListening
                  ? Colors.red.withAlpha(51)
                  : Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: widget.isListening
                  ? Colors.red
                  : Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        );
      },
    );
  }
}
