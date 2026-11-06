import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

final db = FirebaseFirestore.instance;
String dayStr(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String monthStr(DateTime d) => DateFormat('yyyy-MM').format(d);
String money(num v) => '₹${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';
String normPhone(String s) {
  final d = s.replaceAll(RegExp(r'\D'), '');
  return d.length == 10 ? '+91$d' : '+$d';
}

Widget logoutButton() => IconButton(
    icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut());

/// Do NOT await this in UI code: offline, Firestore queues the write and
/// the future only completes once the server acknowledges it.
Future<void> setDelivery(DocumentSnapshot d, double qty, String status, String by) async {
  final m = d.data() as Map<String, dynamic>;
  final rate = (m['rate'] as num).toDouble();
  final amount = status == 'delivered' ? qty * rate : 0.0;
  final old = (m['amount'] as num?)?.toDouble() ?? 0.0;
  final b = db.batch();
  b.update(d.reference, {
    'deliveredQty': status == 'delivered' ? qty : 0,
    'status': status,
    'amount': amount,
    'markedBy': by,
    'markedAt': FieldValue.serverTimestamp(),
  });
  b.update(db.collection('customers').doc(m['customerId']),
      {'balance': FieldValue.increment(amount - old)});
  await b.commit();
}

Future<void> editDelivery(BuildContext context, DocumentSnapshot d) async {
  final m = d.data() as Map<String, dynamic>;
  final t = TextEditingController(
      text: '${m['status'] == 'delivered' ? m['deliveredQty'] : m['qty']}');
  final by = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(m['customerName']),
      content: TextField(
        controller: t,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Litres'),
      ),
      actions: [
        TextButton(
            onPressed: () {
              setDelivery(d, 0, 'missed', by);
              Navigator.pop(ctx);
            },
            child: const Text('Not delivered')),
        FilledButton(
            onPressed: () {
              setDelivery(d, double.tryParse(t.text) ?? 0, 'delivered', by);
              Navigator.pop(ctx);
            },
            child: const Text('Delivered')),
      ],
    ),
  );
}

Icon statusIcon(String s) => s == 'delivered'
    ? const Icon(Icons.check_circle, color: Colors.green)
    : s == 'missed'
        ? const Icon(Icons.cancel, color: Colors.red)
        : const Icon(Icons.schedule, color: Colors.orange);

// ---------- Theme palettes ----------
class Palette {
  final String name;
  final Color primary, container, accent, bg;
  const Palette(this.name, this.primary, this.container, this.accent, this.bg);
}

const palettes = [
  Palette('Fresh blue', Color(0xFF1565C0), Color(0xFFDCEBFA), Color(0xFF29B6F6), Color(0xFFF3F8FD)),
  Palette('Dairy green', Color(0xFF2E7D32), Color(0xFFDFF1E0), Color(0xFFF9A825), Color(0xFFF4FAF2)),
  Palette('Teal & cream', Color(0xFF00796B), Color(0xFFFFEBC2), Color(0xFFFF8F00), Color(0xFFFFF8E8)),
  Palette('Royal purple', Color(0xFF5E35B1), Color(0xFFE6DDF6), Color(0xFFFFB300), Color(0xFFF7F4FD)),
  Palette('Sunrise orange', Color(0xFFE65100), Color(0xFFFFE3CC), Color(0xFF00897B), Color(0xFFFFF6EE)),
];

final paletteIndex = ValueNotifier<int>(0);

Future<void> loadPalette() async {
  try {
    final p = await SharedPreferences.getInstance();
    paletteIndex.value = (p.getInt('palette') ?? 0).clamp(0, palettes.length - 1);
  } catch (_) {}
}

Future<void> savePalette(int i) async {
  paletteIndex.value = i;
  try {
    (await SharedPreferences.getInstance()).setInt('palette', i);
  } catch (_) {}
}

ThemeData themeFor(Palette p) => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: p.bg,
      colorScheme: ColorScheme.fromSeed(seedColor: p.primary).copyWith(
        primary: p.primary,
        onPrimary: Colors.white,
        secondary: p.accent,
        surface: p.bg,
        surfaceContainerLow: p.container,
        surfaceContainer: p.container,
        secondaryContainer: p.container,
        primaryContainer: p.container,
      ),
    );

PreferredSizeWidget appBar(BuildContext c, String title, {List<Widget>? actions}) {
  final cs = Theme.of(c).colorScheme;
  return AppBar(
    title: Text(title),
    actions: actions,
    backgroundColor: cs.primary,
    foregroundColor: Colors.white,
  );
}

List<Widget> topActions() => [
      PopupMenuButton<int>(
        icon: const Icon(Icons.palette),
        tooltip: 'Theme colour',
        onSelected: savePalette,
        itemBuilder: (_) => [
          for (var i = 0; i < palettes.length; i++)
            PopupMenuItem(
              value: i,
              child: Row(children: [
                CircleAvatar(radius: 9, backgroundColor: palettes[i].primary),
                const SizedBox(width: 10),
                Text(palettes[i].name),
              ]),
            ),
        ],
      ),
      logoutButton(),
    ];

Widget bannerImage({double height = 130, String? title}) => ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(fit: StackFit.expand, children: [
          Image.asset('assets/images/banner.png', fit: BoxFit.cover, alignment: Alignment.centerRight),
          if (title != null)
            Positioned(
              left: 16,
              bottom: 14,
              child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    );

Widget emptyState(String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/images/empty.png', width: 240),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ]),
      ),
    );
