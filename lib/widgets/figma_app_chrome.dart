import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class FigmaSegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  const FigmaSegmentOption(
      {required this.value, required this.label, this.icon});
}

class FigmaSegmentControl<T> extends StatelessWidget {
  final List<FigmaSegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const FigmaSegmentControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final ink = Theme.of(context).colorScheme.onPrimary;
    final muted = Theme.of(context).hintColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: FigmaAppColors.fill(context),
        border: Border.all(color: FigmaAppColors.border(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: i == options.length - 1 ? 0 : 4,
                ),
                child: Material(
                  color: options[i].value == selected
                      ? accent
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onChanged(options[i].value),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (options[i].icon != null) ...[
                              Icon(
                                options[i].icon,
                                size: 18,
                                color:
                                    options[i].value == selected ? ink : muted,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                options[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: options[i].value == selected
                                      ? ink
                                      : muted,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FigmaAppColors {
  static Color bg(BuildContext context) => AppColors.of(context).background;
  static Color card(BuildContext context) => AppColors.of(context).surface;
  static Color text(BuildContext context) => AppColors.of(context).text;
  static Color subtext(BuildContext context) => AppColors.of(context).muted;
  static Color border(BuildContext context) => AppColors.of(context).line;
  static Color fill(BuildContext context) => AppColors.of(context).surface2;
  static Color primary(BuildContext context) => AppColors.of(context).accent;
  static Color primaryText(BuildContext context) => AppColors.of(context).accentInk;
}
class FigmaAppShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final int selectedIndex;
  final Widget child;
  final Widget? bottomAction;
  final bool showBack;
  final bool referenceHeader;
  final bool showProfile;
  final bool showBottomNav;
  final List<Widget>? actions;

  const FigmaAppShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selectedIndex,
    required this.child,
    this.bottomAction,
    this.showBack = false,
    this.referenceHeader = false,
    this.showProfile = true,
    this.showBottomNav = false,
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
              referenceHeader: referenceHeader,
              showProfile: showProfile,
              actions: actions,
            ),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: bottomAction == null
          ? (showBottomNav
              ? FigmaBottomNav(selectedIndex: selectedIndex)
              : null)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                bottomAction!,
                if (showBottomNav) FigmaBottomNav(selectedIndex: selectedIndex),
              ],
            ),
    );
  }
}

class _FigmaHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool showBack;
  final bool referenceHeader;
  final bool showProfile;
  final List<Widget>? actions;
  const _FigmaHeader(
      {required this.title,
      required this.subtitle,
      required this.showBack,
      required this.referenceHeader,
      required this.showProfile,
      this.actions});

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final horizontalPadding = compact ? 16.0 : 20.0;
        final profile = FigmaIconButton(
            icon: Icons.person_outline,
            onPressed: () => Navigator.of(context).pushNamed('/profile'));
        return Padding(
            padding: EdgeInsets.fromLTRB(
                horizontalPadding, 12, horizontalPadding, 8),
            child: showBack && referenceHeader
                ? Row(children: [
                    FigmaIconButton(
                        icon: Icons.chevron_left,
                        onPressed: () => Navigator.of(context).maybePop()),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          _title(context, compact),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            _subtitle(context, compact)
                          ]
                        ])),
                    if (actions != null) ...actions!,
                    if (showProfile) ...[const SizedBox(width: 6), profile],
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Row(children: [
                          if (showBack) ...[
                            FigmaIconButton(
                                icon: Icons.chevron_left,
                                onPressed: () =>
                                    Navigator.of(context).maybePop()),
                            const SizedBox(width: 8)
                          ],
                          Expanded(child: _title(context, compact)),
                          if (actions != null) ...actions!,
                          if (showProfile) ...[
                            const SizedBox(width: 6),
                            profile
                          ]
                        ]),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _subtitle(context, compact)
                        ],
                      ]));
      });

  Widget _title(BuildContext context, bool compact) => Text(title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          color: FigmaAppColors.text(context),
          fontSize: compact ? 23 : 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5));
  Widget _subtitle(BuildContext context, bool compact) => Text(subtitle,
      maxLines: compact ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          color: FigmaAppColors.subtext(context),
          fontSize: 14,
          fontWeight: FontWeight.w500));
}

class FigmaBottomNav extends StatelessWidget {
  final int selectedIndex;

  const FigmaBottomNav({super.key, required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _FigmaTab('Home', Icons.home_outlined, '/home'),
      _FigmaTab('Create', Icons.add_circle_outline, '/dashboard'),
      _FigmaTab('Settings', Icons.settings_outlined, '/settings'),
    ];

    return SafeArea(
      top: false,
      child: Container(
        height: 72,
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
                            ? FigmaAppColors.primary(context)
                            : FigmaAppColors.subtext(context),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tabs[i].label,
                        style: TextStyle(
                          color: selectedIndex == i
                              ? FigmaAppColors.primary(context)
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FigmaAppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: AppColors.of(context).highlightGlow,
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
      width: 44,
      height: 44,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon, size: 21),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: FigmaAppColors.fill(context),
          foregroundColor: FigmaAppColors.text(context),
          side: BorderSide(color: FigmaAppColors.border(context)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
      height: 56,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: FigmaAppColors.primary(context),
          foregroundColor: FigmaAppColors.primaryText(context),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        child: child,
      ),
    );
  }
}
