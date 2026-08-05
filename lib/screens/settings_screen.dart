import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppSettings _settings = const AppSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await AppSettingsStore.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _updateSettings(AppSettings settings) async {
    setState(() => _settings = settings);
    await AppSettingsStore.save(settings);
    if (!mounted) return;
    InkNoteApp.maybeOf(context)?.updateSettings(settings);
  }

  Future<void> _clearAllNotes() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all notes?'),
        content: const Text(
          'Every note and folder will be permanently deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await InkDocumentStore.deleteAll();
    await InkFolderStore.deleteAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All notes were deleted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator.adaptive()));
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const BackButtonIcon(),
        ),
        title: const Text('Settings'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
              12,
              MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
              36,
            ),
            children: [
              _SettingsSection(
                title: 'Appearance',
                subtitle: 'Use the device theme or choose a fixed appearance.',
                child: _ThemePreferenceControl(
                  value: _settings.themePreference,
                  onChanged: (value) {
                    _updateSettings(
                      _settings.copyWith(themePreference: value),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: 'Writing',
                subtitle: 'Defaults used when opening the editor.',
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Draw with finger'),
                      subtitle: const Text(
                        'Keep this off when using a stylus for better palm rejection.',
                      ),
                      value: _settings.allowFinger,
                      onChanged: (value) => _updateSettings(
                        _settings.copyWith(allowFinger: value),
                      ),
                    ),
                    const Divider(height: 28),
                    _SliderSetting(
                      title: 'Pen width',
                      valueLabel: _settings.defaultWidth.toStringAsFixed(1),
                      value: _settings.defaultWidth,
                      min: .5,
                      max: 12,
                      divisions: 23,
                      onChanged: (value) => _updateSettings(
                        _settings.copyWith(defaultWidth: value),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SliderSetting(
                      title: 'Stroke smoothing',
                      valueLabel:
                          '${(_settings.defaultSmoothing * 100).round()}%',
                      value: _settings.defaultSmoothing,
                      min: 0,
                      max: 1,
                      divisions: 20,
                      onChanged: (value) => _updateSettings(
                        _settings.copyWith(defaultSmoothing: value),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: 'Library',
                subtitle: 'Choose the default order for notes.',
                child: DropdownButtonFormField<String>(
                  initialValue: _settings.sortBy,
                  decoration: const InputDecoration(labelText: 'Sort notes by'),
                  items: const [
                    DropdownMenuItem(
                      value: 'date_modified',
                      child: Text('Last edited'),
                    ),
                    DropdownMenuItem(
                      value: 'date_created',
                      child: Text('Date created'),
                    ),
                    DropdownMenuItem(value: 'name', child: Text('Name')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _updateSettings(_settings.copyWith(sortBy: value));
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: 'Data',
                subtitle: 'Manage notes stored on this device.',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Delete all notes',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text('Permanently remove every note and folder'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _clearAllNotes,
                ),
              ),
              const SizedBox(height: 26),
              Text(
                'Ink Note 1.1.0',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _ThemePreferenceControl extends StatelessWidget {
  const _ThemePreferenceControl({
    required this.value,
    required this.onChanged,
  });

  final ThemePreference value;
  final ValueChanged<ThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 390) {
          return DropdownButtonFormField<ThemePreference>(
            initialValue: value,
            decoration: const InputDecoration(labelText: 'Theme'),
            items: const [
              DropdownMenuItem(
                value: ThemePreference.system,
                child: Text('Use device setting'),
              ),
              DropdownMenuItem(
                value: ThemePreference.light,
                child: Text('Light'),
              ),
              DropdownMenuItem(
                value: ThemePreference.dark,
                child: Text('Dark'),
              ),
            ],
            onChanged: (selection) {
              if (selection != null) onChanged(selection);
            },
          );
        }

        return SegmentedButton<ThemePreference>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: ThemePreference.system,
              icon: Icon(Icons.brightness_auto_outlined),
              label: Text('System'),
            ),
            ButtonSegment(
              value: ThemePreference.light,
              icon: Icon(Icons.light_mode_outlined),
              label: Text('Light'),
            ),
            ButtonSegment(
              value: ThemePreference.dark,
              icon: Icon(Icons.dark_mode_outlined),
              label: Text('Dark'),
            ),
          ],
          selected: {value},
          onSelectionChanged: (selection) => onChanged(selection.first),
        );
      },
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              valueLabel,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueLabel,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
