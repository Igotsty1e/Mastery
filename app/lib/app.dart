import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'analytics/analytics.dart';
import 'api/api_client.dart';
import 'config.dart';
import 'screens/home_screen.dart';
import 'theme/mastery_theme.dart';

class MasteryApp extends StatelessWidget {
  const MasteryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Provider<ApiClient>(
      create: (_) {
        final client = ApiClient(baseUrl: AppConfig.apiBaseUrl);
        // Wave G4 — bind the analytics tracker to the live ApiClient
        // so every screen / button can call `Analytics.track(...)`
        // without threading the client through. Auth attaches later
        // (after sign-in); the tracker silently buffers events until
        // the auth header is available.
        Analytics.bind(client);
        return client;
      },
      dispose: (_, client) {
        Analytics.unbind();
        client.dispose();
      },
      child: MaterialApp(
        title: 'Mastery',
        debugShowCheckedModeBanner: false,
        theme: MasteryTheme.light(),
        home: const HomeScreen(),
      ),
    );
  }
}
