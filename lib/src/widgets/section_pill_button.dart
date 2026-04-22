import "package:flutter/material.dart";

class SectionPillButton extends StatelessWidget {
  const SectionPillButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.icon,
    this.padding,
    this.minHeight = 44,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final IconData? icon;
  final EdgeInsetsGeometry? padding;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final bool enabled = onPressed != null;

    final Color backgroundColor = !enabled
        ? colorScheme.surfaceContainerHighest.withOpacity(isDark ? 0.42 : 0.58)
        : selected
            ? Color.alphaBlend(
                colorScheme.primary.withOpacity(isDark ? 0.28 : 0.16),
                colorScheme.surfaceContainerHigh,
              )
            : colorScheme.surfaceContainer.withOpacity(isDark ? 0.78 : 0.92);
    final Color borderColor = selected
        ? colorScheme.primary.withOpacity(isDark ? 0.68 : 0.56)
        : colorScheme.outlineVariant.withOpacity(isDark ? 0.72 : 0.86);
    final Color foregroundColor = !enabled
        ? colorScheme.onSurface.withOpacity(isDark ? 0.52 : 0.46)
        : selected
            ? colorScheme.onSurface
            : colorScheme.onSurface.withOpacity(isDark ? 0.9 : 0.82);

    final TextStyle textStyle =
        (theme.textTheme.labelLarge ?? const TextStyle(fontSize: 14)).copyWith(
      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      height: 1.32,
      color: foregroundColor,
    );

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Padding(
              padding:
                  padding ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 17, color: foregroundColor),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    strutStyle: const StrutStyle(
                      forceStrutHeight: true,
                      height: 1.32,
                      leading: 0.1,
                    ),
                    style: textStyle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionPillBadge extends StatelessWidget {
  const SectionPillBadge({
    required this.label,
    this.icon,
    super.key,
  });

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: colorScheme.surfaceContainer.withOpacity(
          theme.brightness == Brightness.dark ? 0.72 : 0.9,
        ),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 17, color: colorScheme.onSurface.withOpacity(0.78)),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: (theme.textTheme.labelLarge ?? const TextStyle(fontSize: 14)).copyWith(
                fontWeight: FontWeight.w600,
                height: 1.32,
                color: colorScheme.onSurface.withOpacity(0.84),
              ),
              strutStyle: const StrutStyle(
                forceStrutHeight: true,
                height: 1.32,
                leading: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
