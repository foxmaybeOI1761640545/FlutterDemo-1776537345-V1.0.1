import "package:flutter/material.dart";

void main() {
  runApp(const RainbowToggleApp());
}

const List<String> _unifiedFontFallback = <String>[
  "Microsoft YaHei UI",
  "Microsoft YaHei",
  "PingFang SC",
  "Noto Sans CJK SC",
  "Noto Sans SC",
  "Source Han Sans SC",
  "Arial Unicode MS",
];

class RainbowToggleApp extends StatelessWidget {
  const RainbowToggleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Rainbow Toggle Demo",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            textStyle: const TextStyle(
              fontFamily: "Segoe UI",
              fontFamilyFallback: _unifiedFontFallback,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      home: const RainbowTogglePage(),
    );
  }
}

class RainbowTogglePage extends StatefulWidget {
  const RainbowTogglePage({super.key});

  @override
  State<RainbowTogglePage> createState() => _RainbowTogglePageState();
}

class _RainbowTogglePageState extends State<RainbowTogglePage>
    with SingleTickerProviderStateMixin {
  static const String _englishText = "Hello World";
  static const String _chineseText = "\u4f60\u597d \u4e16\u754c";
  static const String _toggleButtonLabel = "\u70b9\u51fb\u5207\u6362";

  late final AnimationController _rainbowController;
  int _textIndex = -1;

  @override
  void initState() {
    super.initState();
    _rainbowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _rainbowController.dispose();
    super.dispose();
  }

  void _toggleText() {
    setState(() {
      if (_textIndex == -1) {
        _textIndex = 0;
      } else {
        _textIndex = (_textIndex + 1) % 2;
      }
    });
  }

  String get _displayText {
    if (_textIndex == 0) {
      return _englishText;
    }
    if (_textIndex == 1) {
      return _chineseText;
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                height: 96,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _rainbowController,
                    builder: (BuildContext context, Widget? child) {
                      return RainbowAnimatedText(
                        text: _displayText,
                        progress: _rainbowController.value,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _toggleText,
                child: const Text(_toggleButtonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RainbowAnimatedText extends StatelessWidget {
  const RainbowAnimatedText({
    required this.text,
    required this.progress,
    super.key,
  });

  final String text;
  final double progress;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Color> colors = List<Color>.generate(
      7,
      (int index) {
        final double hue = ((index / 7) + progress) % 1.0;
        return HSVColor.fromAHSV(1, hue * 360, 0.85, 0.95).toColor();
      },
    );

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (Rect bounds) {
          final double width = bounds.width <= 0 ? 1 : bounds.width;
          final double height = bounds.height <= 0 ? 1 : bounds.height;
          return LinearGradient(
            colors: colors,
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(Rect.fromLTWH(0, 0, width, height));
        },
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: "Segoe UI",
            fontFamilyFallback: _unifiedFontFallback,
            fontSize: 56,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
