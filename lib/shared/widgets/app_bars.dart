import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/app_theme_extension.dart';
import '../../app/theme/design_tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Scaffolds & app bars — composed once so every screen uses the same shell.
//
//   HaynLargeTitleScaffold → tab-level screens (Library, Tools, Tasks, Settings).
//                            Apple-style large title that shrinks on scroll.
//   HaynDetailAppBar       → compact AppBar with back, title, actions.
//   HaynModalAppBar        → fullscreen-modal AppBar (X close + Done trailing).
//   HaynScaffold           → generic Scaffold wrapper (only sets background).
// ─────────────────────────────────────────────────────────────────────────────

class HaynScaffold extends StatelessWidget {
  const HaynScaffold({
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.resizeToAvoidBottomInset,
    super.key,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: appBar,
      body: body,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
  }
}

/// Apple-style large-title screen. Composes Scaffold + CustomScrollView +
/// SliverAppBar.large. Callers provide slivers for the body.
class HaynLargeTitleScaffold extends StatelessWidget {
  const HaynLargeTitleScaffold({
    required this.title,
    required this.slivers,
    this.actions,
    this.leading,
    this.scrollController,
    this.bottomNavigationBar,
    this.floatingActionButton,
    super.key,
  });

  final String title;
  final List<Widget> slivers;
  final List<Widget>? actions;
  final Widget? leading;
  final ScrollController? scrollController;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      body: CustomScrollView(
        controller: scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverAppBar.large(
            pinned: true,
            stretch: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            shadowColor: hc.border,
            scrolledUnderElevation: 0.5,
            leading: leading,
            automaticallyImplyLeading: leading != null,
            title: Text(title),
            actions: actions,
            systemOverlayStyle: theme.brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            expandedHeight: 112,
            titleTextStyle: theme.textTheme.titleLarge,
            // The large/expanded title style:
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                start: AppSpacing.md, bottom: AppSpacing.s3,
              ),
              expandedTitleScale: 1.65,
              title: Text(
                title,
                style: theme.textTheme.titleLarge,
              ),
            ),
          ),
          ...slivers,
          const SliverPadding(padding: EdgeInsets.only(bottom: AppSpacing.md)),
        ],
      ),
    );
  }
}

/// Compact AppBar for non-tab screens (detail, picker, sub-page).
/// Back arrow is auto-implied by Navigator (will reverse in RTL).
class HaynDetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HaynDetailAppBar({
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.transparent = false,
    super.key,
  }) : assert(title != null || titleWidget != null);

  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final bool transparent;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hc = context.hc;
    return AppBar(
      toolbarHeight: 52,
      backgroundColor:
          transparent ? Colors.transparent : theme.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      shadowColor: hc.border,
      elevation: 0,
      scrolledUnderElevation: transparent ? 0 : 0.5,
      leading: leading,
      title: titleWidget ?? Text(title!),
      actions: actions,
    );
  }
}

/// Modal AppBar (X close + title + optional Done). Use inside fullscreen modals.
class HaynModalAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HaynModalAppBar({
    required this.title,
    this.onClose,
    this.onDone,
    this.doneLabel,
    this.actions,
    super.key,
  });

  final String title;
  final VoidCallback? onClose;
  final VoidCallback? onDone;
  final String? doneLabel;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hc = context.hc;
    return AppBar(
      toolbarHeight: 52,
      backgroundColor: theme.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        onPressed: () {
          HapticFeedback.selectionClick();
          if (onClose != null) {
            onClose!();
          } else {
            Navigator.of(context).maybePop();
          }
        },
        icon: const Icon(Icons.close_rounded, size: 24),
        color: hc.text2,
      ),
      centerTitle: true,
      title: Text(title),
      actions: [
        if (onDone != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.s2),
            child: TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                onDone!();
              },
              child: Text(
                doneLabel ?? MaterialLocalizations.of(context).okButtonLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: hc.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (actions != null) ...actions!,
      ],
    );
  }
}
