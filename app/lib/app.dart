import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api/api_client.dart';
import 'config.dart';
import 'screens/home_screen.dart';
import 'theme/mastery_theme.dart';

class MasteryApp extends StatelessWidget {
  const MasteryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Provider<ApiClient>(
      create: (_) => ApiClient(baseUrl: AppConfig.apiBaseUrl),
      dispose: (_, client) => client.dispose(),
      child: MaterialApp(
        title: 'Mastery',
        debugShowCheckedModeBanner: false,
        theme: MasteryTheme.light(),
        home: const HomeScreen(),
      ),
    );
  }
}
