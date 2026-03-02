import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../app/role_router.dart';
import 'role_selection_onboarding_screen.dart';
import 'start_flow.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }

        final user = snap.data;
        if (user == null) {
          // Not logged in => Onboarding/Welcome/Auth screens
          return const StartFlow();
        }

        // Logged in => determine role from Firestore
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (_, docSnap) {
            if (docSnap.connectionState == ConnectionState.waiting) {
              return const _Splash();
            }

            final data = docSnap.data?.data();

            // If no user doc yet, create a default (seeker)
            if (data == null) {
              FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                'name': user.displayName ?? '',
                'email': user.email ?? '',
                'role': 'seeker',
                'createdAt': FieldValue.serverTimestamp(),
              });
              return const RoleRouter(role: UserRole.seeker);
            }

            final roleStr = (data?['role'] ?? '').toString();

            // role not chosen yet -> push role selection onboarding
            if (roleStr.isEmpty) {
              return const RoleSelectionOnboardingScreen();
            }

            final role = roleStr == 'provider' ? UserRole.provider : UserRole.seeker;
            return RoleRouter(role: role);
          },
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}