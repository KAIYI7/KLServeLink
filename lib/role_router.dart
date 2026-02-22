import 'package:flutter/material.dart';
import 'seeker_shell.dart';
import 'provider_shell.dart';

enum UserRole { seeker, provider }

class RoleRouter extends StatelessWidget {
  final UserRole role;
  const RoleRouter({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    switch (role) {
      case UserRole.seeker:
        return const SeekerShell();
      case UserRole.provider:
        return const ProviderShell();
    }
  }
}