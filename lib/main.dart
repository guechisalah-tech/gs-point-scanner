import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'number_parser.dart';

void main() => runApp(const GSPointScanner());

class GSPointScanner extends StatelessWidget {
  const GSPointScanner({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'GS Point Scanner',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b54)),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff176b54), brightness: Brightness.dark),
          useMaterial3: true,
        ),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final stt.SpeechToText speech = stt.SpeechToText();
  final TextEditingController scoreController = TextEditingController();

  Excel? workbook;
  List<String> sheetNames = [];
  String sheetName = '';
  List<List<String>> rows = [];
  String fileName = '';

  int headerRow = 0;
  int nameCol = 0;
  int nameCol2 = -1; // عمود ثانٍ اختياري (اللقب + الاسم)
  int scoreCol = 0;
  int studentRow = 1;

  bool listening = false;
  bool speechReady = false;
  bool autoMode = false; // حفظ تلقائي + استماع متواصل
  bool dirty = false;
  String? localeId;
  String recognized = '';
  String status = 'استورد ملف Excel للبدء';

  // ---------- أدوات مساعدة ----------

  String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

  String _cellText(CellValue? v) {
    if (v == null) return '';
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) return _fmt(v.value);
    return v.toString();
  }

  String _colLetter(int i) {
    var n = i;
    var s = '';
    do {
      s = String.fromCharCode(65 + n % 26) + s;
      n = n ~/ 26 - 1;
    } while (n >= 0);
    return s;
  }

  int get colCount {
    var c = 0;
    for (final r in rows) {
      if (r.length > c) c = r.length;
    }
    return c;
  }

  String _at(int r, int c) {
    if (r < 0 || r >= rows.length || c < 0 || c >= rows[r].length) return '';
    return rows[r][c].trim();
  }

  List<String> headers() {
    final n = colCount;
    return List.generate(n, (i) {
      final t = _at(headerRow, i);
      return '${_colLetter(i)} · ${t.isEmpty ? 'عمود ${i + 1}' : t}';
    });
  }

  String rowName(int r) {
    final a = _at(r, nameCol);
    final b = nameCol2 >= 0 ? _at(r, nameCol2) : '';
    return [a, b].where((e) => e.isNotEmpty).join(' ');
  }

  String currentName() {
    final n = rowName(studentRow);
    return n.isEmpty ? '(اسم غير متوفر)' : n;
  }

  String scoreAt(int r) => _at(r, scoreCol);

  int lastStudentRow() {
    if (rows.isEmpty) return 0;
    var last = rows.length - 1;
    while (last > headerRow && rows[last].every((v) => v.trim().isEmpty)) {
      last--;
    }
    return last;
  }

  int get totalStudents {
    var n = 0;
    for (var r = headerRow + 1; r <= lastStudentRow(); r++) {
      if (rowName(r).isNotEmpty) n++;
    }
    return n;
  }

  int get filledStudents {
    var n = 0;
    for (var r = headerRow + 1; r <= lastStudentRow(); r++) {
      if (rowName(r).isNotEmpty && scoreAt(r).isNotEmpty) n++;
    }
    return n;
  }

  bool get finished => studentRow > lastStudentRow();

  void _goTo(int r) {
    studentRow = r;
    recognized = '';
    scoreController.text = r <= lastStudentRow() ? scoreAt(r) : '';
  }

  int _nextRow(int from) {
    var r = from + 1;
    final last = lastStudentRow();
    while (r <= last && rowName(r).isEmpty) {
      r++;
    }
    return r;
  }

  // ---------- استيراد ----------

  Future<void> importExcel() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
    if (result == null || result.files.single.bytes == null) return;
    try {
      final x = Excel.decodeBytes(result.files.single.bytes!);
      if (x.tables.isEmpty) {
        setState(() => status = 'الملف لا يحتوي على أي ورقة');
        return;
      }
      workbook = x;
      sheetNames = x.tables.keys.toList();
      fileName = result.files.single.name;
      dirty = false;
      _loadSheet(sheetNames.first);
    } catch (e) {
      setState(() => status = 'تعذر قراءة الملف (يجب أن يكون .xlsx): $e');
    }
  }

  void _loadSheet(String name) {
    final sh = workbook!.tables[name]!;
    final data = sh.rows
        .map((r) => r.map((c) => _cellText(c?.value)).toList())
        .toList();
    setState(() {
      sheetName = name;
      rows = data;
      headerRow = 0;
      _guessColumns();
      _goTo(_nextRow(headerRow));
      status = 'تم استيراد «$name» — $totalStudents تلميذ';
    });
  }

  void _guessColumns() {
    nameCol = 0;
    nameCol2 = -1;
    final n = colCount;
    int? lastNameCol; // اللقب
    int? firstNameCol; // الاسم
    for (var i = 0; i < n; i++) {
      final h = _at(headerRow, i);
      if (h.contains('لقب')) lastNameCol ??= i;
      if (h.contains('اسم') && !h.contains('لقب')) firstNameCol ??= i;
    }
    if (lastNameCol != null && firstNameCol != null) {
      nameCol = lastNameCol;
      nameCol2 = firstNameCol;
    } else if (firstNameCol != null || lastNameCol != null) {
      nameCol = (firstNameCol ?? lastNameCol)!;
    } else {
      nameCol = n > 1 ? 1 : 0;
    }
    scoreCol = n > 0 ? n - 1 : 0;
  }

  // ---------- التسجيل ----------

  void saveScore() {
    if (rows.isEmpty || finished) {
      setState(() => status = 'انتهت قائمة التلاميذ');
      return;
    }
    final val = double.tryParse(scoreController.text.replaceAll(',', '.').trim());
    if (val == null || val < 0 || val > NumberParser.maxScore) {
      setState(() => status = 'أدخل نقطة صحيحة بين 0 و${NumberParser.maxScore.toInt()}');
      return;
    }
    final text = _fmt(val);
    while (rows[studentRow].length <= scoreCol) {
      rows[studentRow].add('');
    }
    rows[studentRow][scoreCol] = text;
    final sh = workbook?.tables[sheetName];
    if (sh != null) {
      final cell = sh.cell(
          CellIndex.indexByColumnRow(columnIndex: scoreCol, rowIndex: studentRow));
      cell.value = val == val.truncateToDouble()
          ? IntCellValue(val.toInt())
          : DoubleCellValue(val);
    }
    final saved = currentName();
    dirty = true;
    setState(() {
      _goTo(_nextRow(studentRow));
      status = finished
          ? 'اكتملت القائمة ✔ يمكنك تصدير الملف.'
          : 'تم تسجيل $text للتلميذ $saved';
    });
  }

  void previous() {
    var r = studentRow - 1;
    while (r > headerRow && rowName(r).isEmpty) {
      r--;
    }
    if (r > headerRow) setState(() => _goTo(r));
  }

  void skip() {
    if (finished) return;
    setState(() => _goTo(_nextRow(studentRow)));
  }

  // ---------- الصوت ----------

  Future<bool> _initSpeech() async {
    if (speechReady) return true;
    speechReady = await speech.initialize(
      onStatus: (s) {
        if (!mounted) return;
        setState(() => listening = s == 'listening');
      },
      onError: (SpeechRecognitionError e) {
        if (!mounted) return;
        setState(() {
          listening = false;
          status = 'تعذر التعرف الصوتي: ${e.errorMsg}';
        });
      },
    );
    if (speechReady) {
      try {
        final locales = await speech.locales();
        String norm(String s) => s.replaceAll('-', '_').toLowerCase();
        stt.LocaleName? pick;
        for (final l in locales) {
          if (norm(l.localeId) == 'ar_dz') pick = l;
        }
        pick ??= locales.cast<stt.LocaleName?>().firstWhere(
            (l) => norm(l!.localeId).startsWith('ar'),
            orElse: () => null);
        localeId = pick?.localeId;
      } catch (_) {}
    }
    return speechReady;
  }

  Future<void> startListening() async {
    if (finished) return;
    if (speech.isListening) {
      await speech.stop();
      return;
    }
    if (!await _initSpeech()) {
      setState(() => status = 'التعرف الصوتي غير متاح. تحقق من إذن الميكروفون وخدمة Google.');
      return;
    }
    setState(() {
      recognized = '';
      scoreController.clear();
      status = 'استمع... انطق النقطة';
    });
    await speech.listen(
      localeId: localeId,
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 2),
      onResult: _onResult,
    );
  }

  void _onResult(SpeechRecognitionResult r) {
    if (!mounted) return;
    final words = r.recognizedWords;
    final parsed = NumberParser.parse(words);
    setState(() {
      recognized = words;
      if (parsed != null) scoreController.text = _fmt(parsed);
    });
    if (!r.finalResult) return;

    final cmd = NumberParser.command(words);
    if (cmd == VoiceCommand.confirm) {
      saveScore();
    } else if (cmd == VoiceCommand.back) {
      previous();
    } else if (cmd == VoiceCommand.skip) {
      skip();
    } else if (parsed != null && autoMode) {
      saveScore();
    } else if (parsed == null) {
      setState(() => status = 'لم أفهم «$words» — أعد المحاولة أو اكتب النقطة');
    } else {
      setState(() => status = 'راجع النقطة ثم اضغط تأكيد (أو قل: تأكيد)');
    }
    if (autoMode && !finished) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && autoMode && !finished && !speech.isListening) startListening();
      });
    }
  }

  // ---------- التصدير ----------

  Future<void> exportExcel() async {
    if (workbook == null) return;
    final bytes = workbook!.encode();
    if (bytes == null) {
      setState(() => status = 'تعذر إنشاء الملف');
      return;
    }
    final base = fileName.replaceAll(RegExp(r'\.xlsx$', caseSensitive: false), '');
    final out = await FilePicker.platform.saveFile(
      fileName: 'GS_points_$base.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      bytes: Uint8List.fromList(bytes),
    );
    if (out != null) {
      dirty = false;
      setState(() => status = 'تم حفظ الملف ✔');
    }
  }

  // ---------- قائمة التلاميذ ----------

  void showStudents() {
    final last = lastStudentRow();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (_, controller) => ListView.builder(
            controller: controller,
            itemCount: last - headerRow,
            itemBuilder: (_, i) {
              final r = headerRow + 1 + i;
              final sc = scoreAt(r);
              final name = rowName(r);
              return ListTile(
                selected: r == studentRow,
                leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                title: Text(name.isEmpty ? '(بدون اسم)' : name),
                trailing: sc.isEmpty
                    ? const Icon(Icons.radio_button_unchecked, size: 18)
                    : Text(sc, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                onTap: name.isEmpty
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        setState(() => _goTo(r));
                      },
              );
            },
          ),
        ),
      ),
    );
  }

  // ---------- الواجهة ----------

  Widget _colDropdown(String label, int value, List<String> h,
      ValueChanged<int> onChanged, {bool allowNone = false}) {
    final items = <DropdownMenuItem<int>>[
      if (allowNone) const DropdownMenuItem(value: -1, child: Text('— بدون —')),
      ...List.generate(h.length,
          (i) => DropdownMenuItem(value: i, child: Text(h[i], overflow: TextOverflow.ellipsis))),
    ];
    final int v = value < 0 && allowNone
        ? -1
        : value.clamp(0, h.isEmpty ? 0 : h.length - 1).toInt();
    return DropdownButtonFormField<int>(
      value: v,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: items,
      onChanged: (x) {
        if (x != null) setState(() => onChanged(x));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = headers();
    final theme = Theme.of(context);
    final total = totalStudents;
    final filled = filledStudents;
    final done = rows.isNotEmpty && finished;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GS Point Scanner'),
        centerTitle: true,
        actions: [
          if (rows.isNotEmpty)
            IconButton(
              tooltip: 'قائمة التلاميذ',
              icon: const Icon(Icons.list_alt),
              onPressed: showStudents,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            FilledButton.icon(
              onPressed: importExcel,
              icon: const Icon(Icons.file_open),
              label: Text(rows.isEmpty ? 'استيراد ملف Excel' : 'استيراد ملف آخر'),
            ),
            if (fileName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(fileName, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
              ),
            if (rows.isNotEmpty) ...[
              ExpansionTile(
                title: const Text('إعدادات الأعمدة'),
                subtitle: Text('الاسم: ${rowName(headerRow + 1)}  •  النقطة: ${_colLetter(scoreCol)}',
                    style: theme.textTheme.bodySmall),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  if (sheetNames.length > 1) ...[
                    DropdownButtonFormField<String>(
                      value: sheetName,
                      isDense: true,
                      decoration: const InputDecoration(labelText: 'الورقة (Sheet)', isDense: true),
                      items: sheetNames.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                      onChanged: (v) {
                        if (v != null) _loadSheet(v);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  DropdownButtonFormField<int>(
                    value: headerRow.clamp(0, rows.length - 1).toInt(),
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'صف العناوين', isDense: true),
                    items: List.generate(
                        rows.length > 30 ? 30 : rows.length,
                        (i) => DropdownMenuItem(value: i, child: Text('الصف ${i + 1}'))),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          headerRow = v;
                          _guessColumns();
                          _goTo(_nextRow(headerRow));
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  _colDropdown('عمود اسم التلميذ (أو اللقب)', nameCol, h, (v) {
                    nameCol = v;
                    _goTo(_nextRow(headerRow));
                  }),
                  const SizedBox(height: 8),
                  _colDropdown('عمود الاسم الثاني (اختياري)', nameCol2, h, (v) {
                    nameCol2 = v;
                  }, allowNone: true),
                  const SizedBox(height: 8),
                  _colDropdown('عمود النقطة المراد تعبئته', scoreCol, h, (v) {
                    scoreCol = v;
                    _goTo(studentRow);
                  }),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: total == 0 ? 0 : filled / total, minHeight: 6),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text('أُدخلت نقاط $filled من $total',
                    style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
              ),
              Card(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(children: [
                    Text(done ? 'انتهت القائمة' : 'الصف ${studentRow + 1} في الملف',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text(done ? '✔ اكتملت القائمة' : currentName(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    if (!done && scoreAt(studentRow).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('النقطة الحالية: ${scoreAt(studentRow)}',
                            style: theme.textTheme.bodyMedium),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: scoreController,
                enabled: !done,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                    labelText: 'النقطة', hintText: 'مثلاً 15.5', border: OutlineInputBorder()),
                onSubmitted: (_) => saveScore(),
              ),
              if (recognized.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('سمعت: $recognized',
                      textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                ),
              const SizedBox(height: 12),
              SizedBox(
                height: 64,
                child: FilledButton.icon(
                  onPressed: done ? null : startListening,
                  icon: Icon(listening ? Icons.mic : Icons.mic_none, size: 28),
                  label: Text(listening ? 'استمع... (اضغط للإيقاف)' : 'إدخال بالصوت',
                      style: const TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: FilledButton.tonalIcon(
                  onPressed: done ? null : saveScore,
                  icon: const Icon(Icons.check),
                  label: const Text('تأكيد النقطة والانتقال'),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: previous,
                        icon: const Icon(Icons.skip_next),
                        label: const Text('السابق'))),
                const SizedBox(width: 8),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: done ? null : skip,
                        icon: const Icon(Icons.skip_previous),
                        label: const Text('تجاوز'))),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('الوضع التلقائي'),
                subtitle: const Text('يحفظ النقطة فور سماعها ويستمع للتلميذ التالي'),
                value: autoMode,
                onChanged: (v) => setState(() => autoMode = v),
              ),
              Text('أوامر صوتية: «تأكيد» • «السابق» • «تجاوز / غائب»',
                  textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: exportExcel,
                style: dirty
                    ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.tertiary)
                    : null,
                icon: const Icon(Icons.save_alt),
                label: Text(dirty ? 'تصدير Excel (توجد تعديلات غير محفوظة)' : 'تصدير Excel'),
              ),
            ],
            const SizedBox(height: 16),
            Text(status,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          ]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    autoMode = false;
    scoreController.dispose();
    speech.stop();
    super.dispose();
  }
}
