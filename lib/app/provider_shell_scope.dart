import 'package:flutter/widgets.dart';

class ProviderShellScope extends InheritedWidget {
  final int index;
  final ValueChanged<int> setIndex;

  const ProviderShellScope({
    super.key,
    required this.index,
    required this.setIndex,
    required super.child,
  });

  static ProviderShellScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ProviderShellScope>();
  }

  @override
  bool updateShouldNotify(covariant ProviderShellScope oldWidget) {
    return oldWidget.index != index;
  }
}
