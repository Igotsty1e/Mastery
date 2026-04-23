import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api/api_client.dart';
import 'config.dart';
import 'screens/home_screen.dart';

class MasteryApp extends StatelessWidget {
  const MasteryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Provider<ApiClient>(
      create: (_) => ApiClient(baseUrl: AppConfig.apiBaseUrl),
      dispose: (_, client) => client.dispose(),
      child: MaterialApp(
        title: 'Mastery',
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF2563EB),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
