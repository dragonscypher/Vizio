import 'package:flutter/material.dart';

import '../services/tts_service.dart';
import '../utils/settings_helper.dart';
import '../widgets/custom_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  SettingsScreenState createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  bool _saveAlerts = false;
  bool _reduceModel = false;
  String _selectedVoice = 'default';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final bool saveAlerts =
        await SettingsHelper.getBool('saveAlerts', defaultValue: false);
    final bool reduceModel =
        await SettingsHelper.getBool('reduceModel', defaultValue: false);
    final String voice =
        await SettingsHelper.getString('ttsVoice', defaultValue: 'default');

    if (!mounted) {
      return;
    }

    setState(() {
      _saveAlerts = saveAlerts;
      _reduceModel = reduceModel;
      _selectedVoice = voice;
    });
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    await SettingsHelper.setValue(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF04111C),
              Color(0xFF0A1521),
              Color(0xFF12253B),
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Experience controls',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tune how the assistant stores alerts, balances model size, and speaks across the devices you run it on.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                          height: 1.45,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassPanel(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Save Critical Alerts'),
                subtitle: const Text(
                  'Store important warnings locally so they can be reviewed later.',
                ),
                value: _saveAlerts,
                onChanged: (value) {
                  setState(() {
                    _saveAlerts = value;
                  });
                  _updateSetting('saveAlerts', value);
                },
              ),
            ),
            const SizedBox(height: 16),
            GlassPanel(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use Reduced Model'),
                subtitle: const Text(
                  'Prefer lighter inference behavior for lower-memory devices and headset-class hardware.',
                ),
                value: _reduceModel,
                onChanged: (value) {
                  setState(() {
                    _reduceModel = value;
                  });
                  _updateSetting('reduceModel', value);
                },
              ),
            ),
            const SizedBox(height: 16),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TTS Voice',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use the default voice for the broadest compatibility, or try a named voice on platforms that expose one.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                          height: 1.45,
                        ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedVoice,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      filled: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'default',
                        child: Text('Default'),
                      ),
                      DropdownMenuItem(
                        value: 'voice1',
                        child: Text('Voice 1'),
                      ),
                      DropdownMenuItem(
                        value: 'voice2',
                        child: Text('Voice 2'),
                      ),
                    ],
                    onChanged: (String? value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        _selectedVoice = value;
                      });
                      _updateSetting('ttsVoice', value);
                      TtsService.instance.setVoice(value);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
