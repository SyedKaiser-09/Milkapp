import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'common.dart';

class DeliveryHome extends StatelessWidget {
  final String route;
  const DeliveryHome({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    final by = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
    Query q = db.collection('deliveries').where('date', isEqualTo: dayStr(DateTime.now()));
    if (route.isNotEmpty) q = q.where('route', isEqualTo: route);
    return Scaffold(
      appBar: appBar(context, route.isEmpty ? 'Deliveries' : 'Route: $route', actions: topActions()),
      body: StreamBuilder<QuerySnapshot>(
        stream: q.snapshots(),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final docs = s.data!.docs.toList()
            ..sort((a, b) => (a['customerName'] as String).compareTo(b['customerName'] as String));
          if (docs.isEmpty) return emptyState("No list for today yet.\nAsk admin to generate it.");
          final done = docs.where((d) => d['status'] != 'pending').length;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$done / ${docs.length} done', style: Theme.of(c).textTheme.titleMedium),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: done / docs.length),
              ]),
            ),
            Expanded(
              child: ListView(
                children: docs.map((d) {
                  final pending = d['status'] == 'pending';
                  return ListTile(
                    leading: statusIcon(d['status']),
                    title: Text(d['customerName']),
                    subtitle: Text('${d['qty']} L'),
                    onLongPress: () => editDelivery(c, d),
                    trailing: pending
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.edit), onPressed: () => editDelivery(c, d)),
                            FilledButton(
                                onPressed: () => setDelivery(d, (d['qty'] as num).toDouble(), 'delivered', by),
                                child: const Text('Delivered')),
                          ])
                        : IconButton(icon: const Icon(Icons.edit), onPressed: () => editDelivery(c, d)),
                  );
                }).toList(),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
