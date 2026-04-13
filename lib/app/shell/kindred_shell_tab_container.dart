import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// [StatefulShellRoute.navigatorContainerBuilder] that matches go_router’s
/// indexed stack (each branch stays mounted; inactive branches use
/// [Offstage] + [TickerMode]) and animates when a tab becomes visible.
Widget kindredShellTabContainerBuilder(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  List<Widget> children,
) {
  final currentIndex = navigationShell.currentIndex;
  final items = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    final isActive = i == currentIndex;
    items.add(
      Offstage(
        offstage: !isActive,
        child: TickerMode(
          enabled: isActive,
          child: _KindredBranchTabTransition(
            isActive: isActive,
            child: children[i],
          ),
        ),
      ),
    );
  }
  return IndexedStack(
    index: currentIndex,
    sizing: StackFit.expand,
    children: items,
  );
}

class _KindredBranchTabTransition extends StatefulWidget {
  const _KindredBranchTabTransition({
    required this.isActive,
    required this.child,
  });

  final bool isActive;
  final Widget child;

  @override
  State<_KindredBranchTabTransition> createState() => _KindredBranchTabTransitionState();
}

class _KindredBranchTabTransitionState extends State<_KindredBranchTabTransition>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 240);

  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.018),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    if (widget.isActive) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _KindredBranchTabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.forward(from: 0);
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
