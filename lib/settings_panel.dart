import 'package:flutter/material.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  // Simple in-memory state; hook up persistence later.
  bool openAtLogin = false;
  bool showInMenuBar = true;
  bool soundEffects = true;
  bool alwaysPlainText = false;
  String pasteTarget = 'active';
  double historySpan = 3; // 0..4 -> Day..Forever

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(40),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F9),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        height: 540,
        child: Row(
          children: [
            _Sidebar(
              selected: 0,
              onSelected: (_) {},
            ),
            const VerticalDivider(width: 1, thickness: 1, color: Color(0x11000000)),
            Expanded(
              child: _GeneralSettings(
                openAtLogin: openAtLogin,
                showInMenuBar: showInMenuBar,
                soundEffects: soundEffects,
                alwaysPlainText: alwaysPlainText,
                pasteTarget: pasteTarget,
                historySpan: historySpan,
                onChanged: (s) => setState(() {
                  openAtLogin = s.openAtLogin;
                  showInMenuBar = s.showInMenuBar;
                  soundEffects = s.soundEffects;
                  alwaysPlainText = s.alwaysPlainText;
                  pasteTarget = s.pasteTarget;
                  historySpan = s.historySpan;
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  const _Sidebar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final items = const [
      ('General', Icons.settings),
      ('Shortcuts', Icons.keyboard_alt_rounded),
      ('Rules', Icons.rule_folder_outlined),
      ('Subscription', Icons.workspace_premium_outlined),
    ];
    return Container(
      width: 220,
      color: const Color(0xFFEFEFF3),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final (label, icon) = items[index];
          final sel = index == selected;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelected(index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: Colors.black87),
                    const SizedBox(width: 10),
                    Text(label, style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GeneralSettings extends StatelessWidget {
  final bool openAtLogin;
  final bool showInMenuBar;
  final bool soundEffects;
  final bool alwaysPlainText;
  final String pasteTarget; // 'active' | 'clipboard'
  final double historySpan; // 0..4
  final ValueChanged<_SettingsState> onChanged;

  const _GeneralSettings({
    required this.openAtLogin,
    required this.showInMenuBar,
    required this.soundEffects,
    required this.alwaysPlainText,
    required this.pasteTarget,
    required this.historySpan,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: ListView(
        children: [
          const Text('General', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          _row(
            'Open at login',
            Switch(value: openAtLogin, onChanged: (v) => _emit(v: v)),
          ),
          _row(
            'iCloud sync',
            Row(children: [
              const Text('Synced 1 minute ago', style: TextStyle(color: Colors.black45)),
              const SizedBox(width: 10),
              Switch(value: true, onChanged: (_) {}),
            ]),
          ),
          _row('Show in Menu Bar', Switch(value: showInMenuBar, onChanged: (v) => _emit(show: v))),
          _row('Sound effects', Switch(value: soundEffects, onChanged: (v) => _emit(sound: v))),
          const SizedBox(height: 14),
          const Text('Paste Items', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _radio('To active app', 'active'),
          _radio('To clipboard', 'clipboard'),
          const SizedBox(height: 6),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: alwaysPlainText,
            onChanged: (v) => _emit(plain: v ?? false),
            title: const Text('Always paste as Plain Text'),
          ),
          const SizedBox(height: 8),
          const Text('Keep History', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Slider(
            value: historySpan,
            min: 0,
            max: 4,
            divisions: 4,
            label: const ['Day', 'Week', 'Month', 'Year', 'Forever'][0],
            onChanged: (v) => _emit(span: v),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              style: TextButton.styleFrom(backgroundColor: Colors.white),
              onPressed: () {},
              child: const Text('Erase History...'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, Widget trailing) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          trailing,
        ],
      ),
    );
  }

  Widget _radio(String label, String value) {
    return RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      groupValue: pasteTarget,
      onChanged: (v) => _emit(target: v ?? 'active'),
    );
  }

  void _emit({bool? v, bool? show, bool? sound, bool? plain, String? target, double? span}) {
    onChanged(_SettingsState(
      openAtLogin: v ?? openAtLogin,
      showInMenuBar: show ?? showInMenuBar,
      soundEffects: sound ?? soundEffects,
      alwaysPlainText: plain ?? alwaysPlainText,
      pasteTarget: target ?? pasteTarget,
      historySpan: span ?? historySpan,
    ));
  }
}

class _SettingsState {
  final bool openAtLogin;
  final bool showInMenuBar;
  final bool soundEffects;
  final bool alwaysPlainText;
  final String pasteTarget;
  final double historySpan;

  _SettingsState({
    required this.openAtLogin,
    required this.showInMenuBar,
    required this.soundEffects,
    required this.alwaysPlainText,
    required this.pasteTarget,
    required this.historySpan,
  });
}

