import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/tts_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _detections = [];
  List<Map<String, dynamic>> _ocrs = [];
  List<Map<String, dynamic>> _tts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final d = await DatabaseHelper.instance.getAllDetections();
    final o = await DatabaseHelper.instance.getAllOcr();
    final t = await DatabaseHelper.instance.getAllTts();
    setState(() {
      _detections = d;
      _ocrs = o;
      _tts = t;
      _loading = false;
    });
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Semua Riwayat',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text('Semua riwayat akan dihapus permanen.',
            style: TextStyle(color: Color(0xFF999999))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal',
                  style: TextStyle(color: Color(0xFF666666)))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus',
                  style: TextStyle(color: Color(0xFFE57373)))),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseHelper.instance.clearAll();
      _loadAll();
    }
  }

  String _formatDate(String isoDate) {
    final dt = DateTime.parse(isoDate);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    if (diff.inDays < 7) return '${diff.inDays} hari lalu';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // App Bar
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Text('Perpustakaan',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (!_loading &&
                      (_detections.isNotEmpty ||
                          _ocrs.isNotEmpty ||
                          _tts.isNotEmpty))
                    GestureDetector(
                      onTap: _clearAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A1515),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color:
                                  const Color(0xFF8B1A1A).withOpacity(0.5)),
                        ),
                        child: const Text('Hapus Semua',
                            style: TextStyle(
                                color: Color(0xFFE57373), fontSize: 12)),
                      ),
                    ),
                ],
              ),
            ),

            // Tab Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF666666),
                labelStyle: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.grid_view_rounded, size: 13),
                        const SizedBox(width: 4),
                        Text('Deteksi (${_detections.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.document_scanner_rounded, size: 13),
                        const SizedBox(width: 4),
                        Text('OCR (${_ocrs.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.volume_up_rounded, size: 13),
                        const SizedBox(width: 4),
                        Text('TTS (${_tts.length})'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Tab Content
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF4CAF50)))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        // ── Tab Deteksi Objek ──
                        _HistoryList(
                          items: _detections,
                          emptyMessage: 'Belum ada riwayat deteksi',
                          emptyIcon: Icons.grid_view_rounded,
                          color: const Color(0xFF4CAF50),
                          titleBuilder: (item) =>
                              item['detected_object'] as String,
                          subtitleBuilder: (item) {
                            final conf =
                                (item['confidence_score'] as num).toDouble();
                            return 'Kepercayaan: ${(conf * 100).toStringAsFixed(0)}%';
                          },
                          dateField: 'detection_time',
                          onDelete: (item) async {
                            await DatabaseHelper.instance.deleteDetection(
                                item['id_detection'] as int);
                            _loadAll();
                          },
                          onSpeak: (item) => TtsService.instance
                              .speak(item['detected_object'] as String),
                          formatDate: _formatDate,
                        ),

                        // ── Tab OCR ──
                        _HistoryList(
                          items: _ocrs,
                          emptyMessage: 'Belum ada riwayat OCR',
                          emptyIcon: Icons.document_scanner_rounded,
                          color: const Color(0xFF2196F3),
                          titleBuilder: (item) =>
                              item['extracted_text'] as String,
                          subtitleBuilder: (item) {
                            final pt = item['processing_time'];
                            return pt != null
                                ? 'Waktu proses: ${pt}ms'
                                : 'Teks hasil pindai';
                          },
                          dateField: 'ocr_time',
                          onDelete: (item) async {
                            await DatabaseHelper.instance
                                .deleteOcr(item['id_ocr'] as int);
                            _loadAll();
                          },
                          onSpeak: (item) => TtsService.instance
                              .speak(item['extracted_text'] as String),
                          formatDate: _formatDate,
                        ),

                        // ── Tab TTS ──
                        _HistoryList(
                          items: _tts,
                          emptyMessage: 'Belum ada riwayat TTS',
                          emptyIcon: Icons.volume_up_rounded,
                          color: const Color(0xFFFF9800),
                          titleBuilder: (item) =>
                              item['spoken_text'] as String,
                          subtitleBuilder: (_) => 'Teks yang diputar suara',
                          dateField: 'tts_time',
                          onDelete: (item) async {
                            await DatabaseHelper.instance
                                .deleteTts(item['id_tts'] as int);
                            _loadAll();
                          },
                          onSpeak: (item) => TtsService.instance
                              .speak(item['spoken_text'] as String),
                          formatDate: _formatDate,
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

// ── Reusable History List Widget ──
class _HistoryList extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String emptyMessage;
  final IconData emptyIcon;
  final Color color;
  final String Function(Map<String, dynamic>) titleBuilder;
  final String Function(Map<String, dynamic>) subtitleBuilder;
  final String dateField;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final void Function(Map<String, dynamic>) onSpeak;
  final String Function(String) formatDate;

  const _HistoryList({
    required this.items,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.color,
    required this.titleBuilder,
    required this.subtitleBuilder,
    required this.dateField,
    required this.onDelete,
    required this.onSpeak,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(emptyIcon,
                size: 56, color: Colors.white.withOpacity(0.08)),
            const SizedBox(height: 14),
            Text(emptyMessage,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.3), fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final item = items[i];
        return Dismissible(
          key: Key('${item[dateField]}_$i'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => onDelete(item),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF8B1A1A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: Colors.white54),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(emptyIcon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleBuilder(item),
                        style: const TextStyle(
                            color: Color(0xFFCCCCCC),
                            fontSize: 13,
                            height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            subtitleBuilder(item),
                            style: const TextStyle(
                                color: Color(0xFF555555), fontSize: 11),
                          ),
                          const Spacer(),
                          Text(
                            formatDate(item[dateField] as String),
                            style: const TextStyle(
                                color: Color(0xFF555555), fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => onSpeak(item),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B4D3E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.volume_up_rounded,
                        color: Color(0xFF7ED9B8), size: 16),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}