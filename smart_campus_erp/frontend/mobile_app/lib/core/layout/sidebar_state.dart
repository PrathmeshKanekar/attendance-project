import 'package:flutter_riverpod/flutter_riverpod.dart';

class SidebarNotifier extends StateNotifier<bool> {
  // state = true means expanded, false = collapsed
  SidebarNotifier() : super(true);

  void toggle() => state = !state;
  void expand()  => state = true;
  void collapse()=> state = false;
}

final sidebarProvider =
    StateNotifierProvider<SidebarNotifier, bool>((ref) {
  return SidebarNotifier();
});
