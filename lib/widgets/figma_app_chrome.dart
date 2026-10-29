import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class FigmaAppColors {
  static const background = Color(0xFFF7F8FA);
  static const surface = Colors.white;
  static const ink = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const line = Color(0xFFE5E7EB);
  static const accent = Color(0xFF111827);
  static const soft = Color(0xFFF1F3F6);

  static Color bg(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;
  static Color card(BuildContext context) =>
      Theme.of(context).colorScheme.surface;
  static Color text(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
  static Color subtext(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.68);
  static Color border(BuildContext context) => Theme.of(context).dividerColor;
  static Color fill(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHighest;
  static Color primary(BuildContext context) =>
      Theme.of(context).colorScheme.primary;
  static Color primaryText(BuildContext context) =>
      Theme.of(context).colorScheme.onPrimary;
}

class FigmaAppShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final int selectedIndex;
  final Widget child;
  final bool showBack;
  final List<Widget>? actions;

  const FigmaAppShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selectedIndex,
    required this.child,
    this.showBack = false,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FigmaAppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            _FigmaHeader(
              title: title,
              subtitle: subtitle,
              showBack: showBack,
              actions: actions,
            ),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: FigmaBottomNav(selectedIndex: selectedIndex),
    );
  }
}

class _FigmaHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool showBack;
  final List<Widget>? actions;

  const _FigmaHeader({
    required this.title,
    required this.subtitle,
    required this.showBack,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final horizontalPadding = compact ? 12.0 : 24.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
            children: [
              if (showBack) ...[
                FigmaIconButton(
                  icon: Icons.chevron_left,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: FigmaAppColors.text(context),
                    fontSize: compact ? 21 : 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (actions != null) ...actions!,
              if (AuthService().isAdmin) ...[
                const SizedBox(width: 6),
                FigmaIconButton(
                  icon: Icons.admin_panel_settings_outlined,
                  onPressed: () => Navigator.of(context).pushNamed('/admin'),
                ),
              ],
              const SizedBox(width: 6),
              FigmaIconButton(
                icon: Icons.person_outline,
                onPressed: () => Navigator.of(context).pushNamed('/profile'),
              ),
            ],
          ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: FigmaAppColors.subtext(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class FigmaBottomNav extends StatelessWidget {
  final int selectedIndex;

  const FigmaBottomNav({super.key, required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _FigmaTab('Home', Icons.home_outlined, '/home'),
      _FigmaTab('Create', Icons.add_circle_outline, '/dashboard'),
      _FigmaTab('Config', Icons.settings_outlined, '/settings'),
    ];

    return SafeArea(
      top: false,
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: FigmaAppColors.card(context),
          border:
              Border(top: BorderSide(color: FigmaAppColors.border(context))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: InkWell(
                  onTap: selectedIndex == i
                      ? null
                      : () => Navigator.of(context).pushReplacementNamed(
                            tabs[i].route,
                          ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        tabs[i].icon,
                        size: 21,
                        color: selectedIndex == i
                            ? FigmaAppColors.text(context)
                            : FigmaAppColors.subtext(context),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tabs[i].label,
                        style: TextStyle(
                          color: selectedIndex == i
                              ? FigmaAppColors.text(context)
                              : FigmaAppColors.subtext(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FigmaTab {
  final String label;
  final IconData icon;
  final String route;

  const _FigmaTab(this.label, this.icon, this.route);
}

class FigmaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  const FigmaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? FigmaAppColors.card(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FigmaAppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class FigmaIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const FigmaIconButton({
    super.key,
    required this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: FigmaAppColors.fill(context),
          foregroundColor: FigmaAppColors.text(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class FigmaPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const FigmaPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );

    return SizedBox(
      height: 52,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: FigmaAppColors.primary(context),
          foregroundColor: FigmaAppColors.primaryText(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        child: child,
      ),
    );
  }
}
