import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'common.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int i = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: appBar(context, i == 0 ? 'Today' : 'Customers', actions: topActions()),
        body: i == 0 ? const TodayTab() : const CustomersTab(),
        floatingActionButton: i == 1 ? FloatingActionButton(onPressed: () => addCustomer(context), child: const Icon(Icons.add)) : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (v) => setState(() => i = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.local_shipping), label: 'Today'),
            NavigationDestination(icon: Icon(Icons.people), label: 'Customers'),
          ],
        ),
      );
}

class TodayTab extends StatelessWidget {
  const TodayTab({super.key});

  Future<void> generate(BuildContext c) async {
    final d = dayStr(DateTime.now());
    final existing = (await db.collection('deliveries').where('date', isEqualTo: d).get()).docs.map((e) => e.id).toSet();
    final custs = await db.collection('customers').where('active', isEqualTo: true).get();
    final b = db.batch();
    var n = 0;
    for (final x in custs.docs) {
      final m = x.data();
      final id = '${d}_${x.id}';
      if (m['paused'] == true || existing.contains(id)) continue;
      b.set(db.collection('deliveries').doc(id), {
        'customerId': x.id, 'customerName': m['name'], 'customerPhone': m['phone'],
        'route': m['route'] ?? '', 'date': d, 'month': d.substring(0, 7),
        'qty': m['defaultQty'], 'rate': m['rate'], 'status': 'pending',
        'deliveredQty': 0, 'amount': 0,
      });
      n++;
    }
    await b.commit();
    if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('Added $n deliveries')));
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot>(
        stream: db.collection('deliveries').where('date', isEqualTo: dayStr(DateTime.now())).snapshots(),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final docs = s.data!.docs.toList()..sort((a, b) => (a['customerName'] as String).compareTo(b['customerName'] as String));
          final done = docs.where((d) => d['status'] == 'delivered').length;
          final missed = docs.where((d) => d['status'] == 'missed').length;
          final planned = docs.fold<double>(0, (t, d) => t + (d['qty'] as num));
          final out = docs.fold<double>(0, (t, d) => t + (d['deliveredQty'] as num));
          return ListView(children: [
            bannerImage(height: 110, title: 'Today'),
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(DateFormat('EEEE, d MMM').format(DateTime.now()), style: Theme.of(c).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Delivered $done / ${docs.length}   •   Missed $missed'),
                  Text('Litres ${out.toStringAsFixed(1)} / ${planned.toStringAsFixed(1)}'),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    OutlinedButton.icon(onPressed: () => generate(c), icon: const Icon(Icons.playlist_add), label: const Text("Generate list")),
                    FilledButton.icon(onPressed: () => manualEntry(c), icon: const Icon(Icons.add), label: const Text('Add entry')),
                  ]),
                ]),
              ),
            ),
            ...docs.map((d) => ListTile(
                  leading: statusIcon(d['status']),
                  title: Text(d['customerName']),
                  subtitle: Text('${d['route']}  •  ${d['qty']} L'),
                  onTap: () => editDelivery(c, d),
                )),
          ]);
        },
      );
}

class CustomersTab extends StatelessWidget {
  const CustomersTab({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot>(
        stream: db.collection('customers').orderBy('name').snapshots(),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final docs = s.data!.docs;
          if (docs.isEmpty) return emptyState('No customers yet.\nTap + to add one.');
          return ListView(
            children: docs.map((d) => ListTile(
                  title: Text(d['name']),
                  subtitle: Text('${d['route']}  •  ${d['defaultQty']} L  •  ${money(d['rate'])}/L${d['paused'] == true ? '  •  PAUSED' : ''}'),
                  trailing: Text(money(d['balance']), style: TextStyle(color: (d['balance'] as num) > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => BillPage(customerId: d.id))),
                )).toList(),
          );
        },
      );
}

Future<void> addCustomer(BuildContext context) async {
  final name = TextEditingController(), phone = TextEditingController(), route = TextEditingController(),
      qty = TextEditingController(text: '1'), rate = TextEditingController();
  Widget f(String l, TextEditingController c, {bool num = false}) => TextField(
      controller: c, keyboardType: num ? const TextInputType.numberWithOptions(decimal: true) : null, decoration: InputDecoration(labelText: l));
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add customer'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        f('Name', name), f('Mobile (10 digits)', phone, num: true), f('Route', route),
        f('Litres per day', qty, num: true), f('Rate per litre (₹)', rate, num: true),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            db.collection('customers').add({
              'name': name.text.trim(), 'phone': normPhone(phone.text), 'route': route.text.trim(),
              'defaultQty': double.tryParse(qty.text) ?? 1, 'rate': double.tryParse(rate.text) ?? 0,
              'active': true, 'paused': false, 'balance': 0,
            });
            Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class BillPage extends StatefulWidget {
  final String customerId;
  const BillPage({super.key, required this.customerId});
  @override
  State<BillPage> createState() => _BillPageState();
}

class _BillPageState extends State<BillPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  void addPayment(Map<String, dynamic> cust) {
    final amt = TextEditingController();
    String mode = 'cash';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Record payment'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: amt, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₹)')),
            DropdownButton<String>(value: mode, items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'upi', child: Text('UPI')),
            ], onChanged: (v) => set(() => mode = v!)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final a = double.tryParse(amt.text) ?? 0;
                if (a > 0) {
                  final now = DateTime.now();
                  final b = db.batch();
                  b.set(db.collection('payments').doc(), {
                    'customerId': widget.customerId, 'customerPhone': cust['phone'], 'amount': a,
                    'mode': mode, 'date': dayStr(now), 'month': monthStr(now),
                  });
                  b.update(db.collection('customers').doc(widget.customerId), {'balance': FieldValue.increment(-a)});
                  b.commit();
                }
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = monthStr(month);
    return StreamBuilder<DocumentSnapshot>(
      stream: db.collection('customers').doc(widget.customerId).snapshots(),
      builder: (c, cs) {
        if (!cs.hasData || !cs.data!.exists) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final cust = cs.data!.data() as Map<String, dynamic>;
        return Scaffold(
          appBar: appBar(c, cust['name']),
          floatingActionButton: FloatingActionButton.extended(onPressed: () => addPayment(cust), icon: const Icon(Icons.payments), label: const Text('Payment')),
          body: StreamBuilder<QuerySnapshot>(
            stream: db.collection('deliveries').where('customerId', isEqualTo: widget.customerId).where('month', isEqualTo: m).snapshots(),
            builder: (c, ds) => StreamBuilder<QuerySnapshot>(
              stream: db.collection('payments').where('customerId', isEqualTo: widget.customerId).where('month', isEqualTo: m).snapshots(),
              builder: (c, ps) {
                if (!ds.hasData || !ps.hasData) return const Center(child: CircularProgressIndicator());
                final del = ds.data!.docs.where((d) => d['status'] != 'pending').toList()..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
                final litres = del.fold<double>(0, (s, d) => s + (d['deliveredQty'] as num));
                final bill = del.fold<double>(0, (s, d) => s + (d['amount'] as num));
                final paid = ps.data!.docs.fold<double>(0, (s, d) => s + (d['amount'] as num));
                return ListView(children: [
                  SwitchListTile(
                    title: const Text('Paused (skip daily list)'),
                    value: cust['paused'] == true,
                    onChanged: (v) => db.collection('customers').doc(widget.customerId).update({'paused': v}),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(onPressed: () => manualEntry(c, customerId: widget.customerId), icon: const Icon(Icons.add), label: const Text('Add delivery entry')),
                    ),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => month = DateTime(month.year, month.month - 1))),
                    Text(DateFormat('MMMM yyyy').format(month), style: Theme.of(c).textTheme.titleLarge),
                    IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => month = DateTime(month.year, month.month + 1))),
                  ]),
                  Card(
                    margin: const EdgeInsets.all(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        _r('Litres', litres.toStringAsFixed(1)),
                        _r('Bill', money(bill)),
                        _r('Paid', money(paid)),
                        const Divider(),
                        _r('Total balance due', money(cust['balance']), bold: true),
                      ]),
                    ),
                  ),
                  ...del.map((d) => ListTile(
                        dense: true,
                        leading: statusIcon(d['status']),
                        title: Text(DateFormat('EEE, d MMM').format(DateTime.parse(d['date']))),
                        trailing: Text(d['status'] == 'delivered' ? '${d['deliveredQty']} L  •  ${money(d['amount'])}' : 'Missed'),
                        onTap: () => editDelivery(c, d),
                      )),
                  const SizedBox(height: 80),
                ]);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _r(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ]),
      );
}

Future<void> manualEntry(BuildContext context, {String? customerId}) async {
  final snap = await db.collection('customers').orderBy('name').get();
  if (snap.docs.isEmpty || !context.mounted) return;
  var sel = snap.docs.firstWhere((d) => d.id == customerId, orElse: () => snap.docs.first);
  var date = DateTime.now();
  final qty = TextEditingController(text: '${sel['defaultQty']}');
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Add delivery entry'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButton<String>(
            isExpanded: true,
            value: sel.id,
            items: snap.docs.map((d) => DropdownMenuItem(value: d.id, child: Text(d['name']))).toList(),
            onChanged: (v) => set(() {
              sel = snap.docs.firstWhere((d) => d.id == v);
              qty.text = '${sel['defaultQty']}';
            }),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(DateFormat('EEE, d MMM yyyy').format(date)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final p = await showDatePicker(
                context: ctx,
                initialDate: date,
                firstDate: DateTime.now().subtract(const Duration(days: 400)),
                lastDate: DateTime.now(),
              );
              if (p != null) set(() => date = p);
            },
          ),
          TextField(
            controller: qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Litres delivered'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final q = double.tryParse(qty.text) ?? 0;
              final d = dayStr(date);
              final ref = db.collection('deliveries').doc('${d}_${sel.id}');
              final ex = await ref.get();
              final m = sel.data();
              final rate = ex.exists ? (ex['rate'] as num).toDouble() : (m['rate'] as num).toDouble();
              final old = ex.exists ? ((ex['amount'] as num?)?.toDouble() ?? 0.0) : 0.0;
              final amount = q * rate;
              final by = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
              final b = db.batch();
              b.set(ref, {
                'customerId': sel.id, 'customerName': m['name'], 'customerPhone': m['phone'],
                'route': m['route'] ?? '', 'date': d, 'month': d.substring(0, 7),
                'qty': ex.exists ? ex['qty'] : m['defaultQty'], 'rate': rate,
                'status': 'delivered', 'deliveredQty': q, 'amount': amount,
                'markedBy': by, 'markedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
              b.update(db.collection('customers').doc(sel.id), {'balance': FieldValue.increment(amount - old)});
              b.commit();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
