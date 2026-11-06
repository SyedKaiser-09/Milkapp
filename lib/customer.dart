import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'common.dart';

class CustomerHome extends StatefulWidget {
  final String phone;
  const CustomerHome({super.key, required this.phone});
  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final m = monthStr(month);
    final dq = db.collection('deliveries').where('customerPhone', isEqualTo: widget.phone).where('month', isEqualTo: m);
    final pq = db.collection('payments').where('customerPhone', isEqualTo: widget.phone).where('month', isEqualTo: m);
    final cq = db.collection('customers').where('phone', isEqualTo: widget.phone).limit(1);
    return Scaffold(
      appBar: appBar(context, 'MahaNanda Dairy', actions: topActions()),
      body: StreamBuilder<QuerySnapshot>(
        stream: dq.snapshots(),
        builder: (c, ds) => StreamBuilder<QuerySnapshot>(
          stream: pq.snapshots(),
          builder: (c, ps) => StreamBuilder<QuerySnapshot>(
            stream: cq.snapshots(),
            builder: (c, cs) {
              if (!ds.hasData || !ps.hasData || !cs.hasData) return const Center(child: CircularProgressIndicator());
              final del = ds.data!.docs.where((d) => d['status'] != 'pending').toList()
                ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
              final litres = del.fold<double>(0, (s, d) => s + (d['deliveredQty'] as num));
              final bill = del.fold<double>(0, (s, d) => s + (d['amount'] as num));
              final paid = ps.data!.docs.fold<double>(0, (s, d) => s + (d['amount'] as num));
              final bal = cs.data!.docs.isEmpty ? 0 : (cs.data!.docs.first['balance'] as num);
              return ListView(children: [
                bannerImage(height: 120, title: 'My Milk Deliveries'),
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
                      _row('Delivered', '${litres.toStringAsFixed(1)} L'),
                      _row('Bill this month', money(bill)),
                      _row('Paid this month', money(paid)),
                      const Divider(),
                      _row('Total balance due', money(bal), bold: true),
                    ]),
                  ),
                ),
                if (del.isEmpty) SizedBox(height: 280, child: emptyState('No deliveries this month')),
                ...del.map((d) => ListTile(
                      leading: statusIcon(d['status']),
                      title: Text(DateFormat('EEE, d MMM').format(DateTime.parse(d['date']))),
                      trailing: Text(d['status'] == 'delivered' ? '${d['deliveredQty']} L' : 'Missed'),
                    )),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _row(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ]),
      );
}
