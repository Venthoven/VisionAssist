import 'package:flutter/material.dart';
import '../services/tts_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _speechRate = 0.5;
  double _pitch = 1.0;
  bool _talkbackEnabled = true;
  bool _hapticEnabled = true;
  String _selectedLang = 'id-ID';

  final List<Map<String, String>> _languages = [
    {'code': 'id-ID', 'name': 'Bahasa Indonesia'},
    {'code': 'en-US', 'name': 'English (US)'},
    {'code': 'en-GB', 'name': 'English (UK)'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'Pengaturan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                children: [
                  _SectionHeader(title: 'AKSESIBILITAS'),
                  _ToggleRow(
                    icon: Icons.accessibility_new_rounded,
                    iconColor: const Color(0xFF4CAF50),
                    title: 'TalkBack',
                    subtitle: 'Umpan balik suara untuk layar',
                    value: _talkbackEnabled,
                    onChanged: (v) => setState(() => _talkbackEnabled = v),
                  ),
                  const SizedBox(height: 8),
                  _ToggleRow(
                    icon: Icons.vibration_rounded,
                    iconColor: const Color(0xFF2196F3),
                    title: 'Feedback Haptic',
                    subtitle: 'Getaran saat objek terdeteksi',
                    value: _hapticEnabled,
                    onChanged: (v) => setState(() => _hapticEnabled = v),
                  ),
                  const SizedBox(height: 16),

                  _SectionHeader(title: 'TEXT-TO-SPEECH'),
                  _SliderRow(
                    icon: Icons.speed_rounded,
                    iconColor: const Color(0xFFFF9800),
                    title: 'Kecepatan Bicara',
                    value: _speechRate,
                    min: 0.3,
                    max: 1.5,
                    displayValue: '${_speechRate.toStringAsFixed(1)}x',
                    onChanged: (v) {
                      setState(() => _speechRate = v);
                      TtsService.instance.setSpeechRate(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  _SliderRow(
                    icon: Icons.record_voice_over_rounded,
                    iconColor: const Color(0xFF9C27B0),
                    title: 'Nada Suara',
                    value: _pitch,
                    min: 0.5,
                    max: 2.0,
                    displayValue: '${_pitch.toStringAsFixed(1)}',
                    onChanged: (v) {
                      setState(() => _pitch = v);
                      TtsService.instance.setPitch(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  _DropdownRow(
                    icon: Icons.language_rounded,
                    iconColor: const Color(0xFF2196F3),
                    title: 'Bahasa TTS',
                    value: _selectedLang,
                    options: _languages,
                    onChanged: (v) {
                      setState(() => _selectedLang = v!);
                      TtsService.instance.setLanguage(v!);
                    },
                  ),
                  const SizedBox(height: 8),
                  // Test TTS
                  GestureDetector(
                    onTap: () {
                      TtsService.instance.speak(
                        _selectedLang == 'id-ID'
                            ? 'Halo, ini adalah uji coba suara VisionAssist'
                            : 'Hello, this is a VisionAssist voice test',
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B4D3E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2E6B57)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_circle_outline_rounded, color: Color(0xFF7ED9B8), size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Uji Coba Suara',
                            style: TextStyle(color: Color(0xFF7ED9B8), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  _SectionHeader(title: 'MODEL AI'),
                  _InfoRow(
                    icon: Icons.memory_rounded,
                    iconColor: const Color(0xFF4CAF50),
                    title: 'Model Deteksi',
                    value: 'ML Kit Object Detection',
                    badge: 'AKTIF',
                    badgeColor: const Color(0xFF1B4D3E),
                    badgeTextColor: const Color(0xFF7ED9B8),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.text_fields_rounded,
                    iconColor: const Color(0xFF2196F3),
                    title: 'Model OCR',
                    value: 'Google ML Kit Text Recognition',
                    badge: 'AKTIF',
                    badgeColor: const Color(0xFF0D2137),
                    badgeTextColor: const Color(0xFF64B5F6),
                  ),
                  
                  const SizedBox(height: 16),

                  _SectionHeader(title: 'TENTANG'),
                  _InfoRow(
                    icon: Icons.info_outline_rounded,
                    iconColor: const Color(0xFF666666),
                    title: 'Versi Aplikasi',
                    value: '1.0.0',
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.school_rounded,
                    iconColor: const Color(0xFF666666),
                    title: 'Pengembang',
                    value: 'Willy Fernando — Politeknik Negeri Batam',
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

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF555555),
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
                Text(subtitle, style: const TextStyle(color: Color(0xFF666666), fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF4CAF50),
            activeTrackColor: const Color(0xFF1B4D3E),
            inactiveThumbColor: const Color(0xFF555555),
            inactiveTrackColor: const Color(0xFF2A2A2A),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final double value;
  final double min;
  final double max;
  final String displayValue;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.displayValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(displayValue, style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 12)),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              activeTrackColor: iconColor,
              inactiveTrackColor: const Color(0xFF2A2A2A),
              thumbColor: iconColor,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final List<Map<String, String>> options;
  final ValueChanged<String?> onChanged;

  const _DropdownRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14))),
          DropdownButton<String>(
            value: value,
            dropdownColor: const Color(0xFF1E1E1E),
            underline: const SizedBox(),
            style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF666666), size: 18),
            items: options.map((o) => DropdownMenuItem(
              value: o['code'],
              child: Text(o['name']!),
            )).toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final String? badge;
  final Color? badgeColor;
  final Color? badgeTextColor;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    this.badge,
    this.badgeColor,
    this.badgeTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 13)),
                Text(value, style: const TextStyle(color: Color(0xFF666666), fontSize: 11)),
              ],
            ),
          ),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: badgeTextColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
