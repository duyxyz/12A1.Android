import 'package:flutter/material.dart';

class TabHeader extends StatelessWidget {
  final String title;

  const TabHeader({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Center(
        child: Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}
