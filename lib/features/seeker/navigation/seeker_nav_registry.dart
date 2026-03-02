import 'seeker_nav_controller.dart';

class SeekerNavRegistry {
  SeekerNavController? current;
  SeekerNavRegistry._();
  static final SeekerNavRegistry I = SeekerNavRegistry._();
}