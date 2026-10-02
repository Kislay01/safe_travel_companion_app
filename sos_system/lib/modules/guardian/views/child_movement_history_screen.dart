import 'package:flutter/material.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:sos_system/core/user_paths.dart';
import 'package:sos_system/modules/auth/controllers/shared_preference_data.dart';
import 'package:sos_system/modules/child/views/movement_history_screen.dart';

/// Guardian view: pick a linked child, then see that child's journeys.
class ChildMovementHistory extends StatefulWidget {
  const ChildMovementHistory({super.key});

  @override
  State<ChildMovementHistory> createState() => _ChildMovementHistoryState();
}

class _ChildMovementHistoryState extends State<ChildMovementHistory> {
  List<Map<String, String>>? _children;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = SharedPreferenceData();
    await prefs.getSharedPreferenceData();
    final docs = await UserPaths.childrenOf(prefs.email);
    if (!mounted) return;
    setState(() {
      _children = docs
          .map((d) => {
                'email': d.id,
                'name': (d.data()['name'] ?? d.id).toString(),
              })
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = _children;
    return Scaffold(
      appBar: const CustomAppBar(title: "Child Movement History"),
      body: children == null
          ? const Center(child: CircularProgressIndicator())
          : children.isEmpty
              ? const Center(child: Text("No linked children yet"))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: children.length,
                  itemBuilder: (context, i) {
                    final c = children[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.child_care, color: Colors.blue),
                        title: Text(c['name']!),
                        subtitle: Text(c['email']!),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => MovementHistoryScreen(
                            childEmail: c['email'],
                            title: "${c['name']}'s journeys",
                          ),
                        )),
                      ),
                    );
                  },
                ),
    );
  }
}
