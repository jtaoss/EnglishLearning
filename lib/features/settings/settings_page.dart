import 'dart:async';

import 'package:flutter/material.dart';
import 'package:english_learning/app/app_settings.dart';

final class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.settings});
  final AppSettings settings;
  static const Key themeModeKey = Key('theme-mode');
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, child) => Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Theme', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 480 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                      return DropdownButton<ThemeMode>(
                        key: themeModeKey,
                        isExpanded: true,
                        value: settings.themeMode,
                        items: const [
                          DropdownMenuItem(
                            value: ThemeMode.system,
                            child: Text('System'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.light,
                            child: Text('Light'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.dark,
                            child: Text('Dark'),
                          ),
                        ],
                        onChanged: (mode) {
                          if (mode != null) {
                            unawaited(settings.setThemeMode(mode));
                          }
                        },
                      );
                    }
                    return SegmentedButton<ThemeMode>(
                      key: themeModeKey,
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (selection) =>
                          unawaited(settings.setThemeMode(selection.first)),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
