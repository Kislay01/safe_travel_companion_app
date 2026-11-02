import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sos_system/core/app_theme.dart';
import 'package:sos_system/services/profile_service.dart';

/// Read-only list of the medical details that are filled in.
class MedicalDetails extends StatelessWidget {
  final MedicalInfo info;
  final String emptyText;
  const MedicalDetails({super.key, required this.info, this.emptyText = 'No medical info added yet.'});

  @override
  Widget build(BuildContext context) {
    final muted = TG.mutedOf(context);
    if (info.isEmpty) {
      return Text(emptyText, style: TextStyle(fontSize: 13, color: muted));
    }
    final rows = <(IconData, String, String)>[
      if (info.bloodGroup.isNotEmpty) (Icons.bloodtype_outlined, 'Blood group', info.bloodGroup),
      if (info.allergies.isNotEmpty) (Icons.warning_amber_rounded, 'Allergies', info.allergies),
      if (info.conditions.isNotEmpty) (Icons.monitor_heart_outlined, 'Conditions', info.conditions),
      if (info.medications.isNotEmpty) (Icons.medication_outlined, 'Medicines', info.medications),
      if (info.notes.isNotEmpty) (Icons.sticky_note_2_outlined, 'Emergency note', info.notes),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (icon, label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: label == 'Allergies' ? TG.sos : TG.accentTextOf(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: 12, color: muted)),
                      Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Edit sheet for the child's own medical card. Returns the saved info, or null.
Future<MedicalInfo?> showMedicalEditSheet(BuildContext context, {required String email, required MedicalInfo current}) {
  return showModalBottomSheet<MedicalInfo>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: TG.surfaceOf(context),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _MedicalSheet(email: email, current: current),
  );
}

class _MedicalSheet extends StatefulWidget {
  final String email;
  final MedicalInfo current;
  const _MedicalSheet({required this.email, required this.current});

  @override
  State<_MedicalSheet> createState() => _MedicalSheetState();
}

class _MedicalSheetState extends State<_MedicalSheet> {
  late String _blood = widget.current.bloodGroup;
  late final _allergies = TextEditingController(text: widget.current.allergies);
  late final _conditions = TextEditingController(text: widget.current.conditions);
  late final _meds = TextEditingController(text: widget.current.medications);
  late final _notes = TextEditingController(text: widget.current.notes);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _allergies.dispose();
    _conditions.dispose();
    _meds.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final info = MedicalInfo(
      bloodGroup: _blood,
      allergies: _allergies.text,
      conditions: _conditions.text,
      medications: _meds.text,
      notes: _notes.text,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ProfileService.saveMedical(widget.email, info);
      if (mounted) Navigator.of(context).pop(info);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save. Check your internet.';
        });
      }
    }
  }

  Widget _field(TextEditingController c, String label, String hint) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          controller: c,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, hintText: hint, counterText: ''),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final muted = TG.mutedOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: TG.lineOf(context), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Medical card', style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Sent to your guardians with every SOS. Fill only what you are comfortable sharing.',
                style: TextStyle(fontSize: 13, color: muted)),
            const SizedBox(height: 16),
            Text('Blood group', style: TextStyle(fontSize: 13, color: muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in MedicalInfo.bloodGroups)
                  ChoiceChip(
                    label: Text(g),
                    selected: _blood == g,
                    onSelected: (sel) => setState(() => _blood = sel ? g : ''),
                  ),
              ],
            ),
            _field(_allergies, 'Allergies', 'e.g. penicillin, peanuts'),
            _field(_conditions, 'Conditions', 'e.g. asthma, epilepsy'),
            _field(_meds, 'Medicines', 'e.g. inhaler, insulin'),
            _field(_notes, 'Emergency note', 'e.g. inhaler is in my bag'),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: TG.sos, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save medical card'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Guardian view of a child's medical card.
Future<void> showChildMedicalSheet(BuildContext context, {required String childEmail, required String childName}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: TG.surfaceOf(context),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: TG.lineOf(ctx), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text("$childName's medical card", style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          FutureBuilder<MedicalInfo>(
            future: ProfileService.loadMedical(childEmail),
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return MedicalDetails(
                info: snap.data ?? const MedicalInfo(),
                emptyText: '$childName hasn’t added medical info yet.',
              );
            },
          ),
        ],
      ),
    ),
  );
}
