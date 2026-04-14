// lib/features/herd/presentation/sheets/add_asset_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../../data/models/models.dart';
import '../../../../services/session_manager.dart';
import '../../../../shared/widgets/shared_widgets.dart';

class AddAssetSheet extends StatefulWidget {
  final Asset? existing;
  final Future<void> Function(Asset) onSaved;

  const AddAssetSheet({super.key, this.existing, required this.onSaved});

  @override
  State<AddAssetSheet> createState() => _AddAssetSheetState();
}

class _AddAssetSheetState extends State<AddAssetSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tagCtrl;
  late final TextEditingController _breedCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _notesCtrl;
  
  late AssetCategory _category;
  late AssetStatus _status;
  DateTime? _dateOfBirth;
  bool _saving = false;
  
  final userId = SessionManager.instance.currentUserId;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _tagCtrl    = TextEditingController(text: e?.tagName ?? '');
    _breedCtrl  = TextEditingController(text: e?.breedType ?? '');
    _weightCtrl = TextEditingController(text: e?.weightKg?.toStringAsFixed(1) ?? '');
    _notesCtrl  = TextEditingController(text: e?.healthNotes ?? '');
    _category   = e?.category ?? AssetCategory.livestock;
    _status     = e?.status ?? AssetStatus.active;
    _dateOfBirth = e?.dateOfBirth;
  }

  @override
  void dispose() {
    _tagCtrl.dispose();
    _breedCtrl.dispose();
    _weightCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    
    try {
      final asset = Asset(
        assetId: widget.existing?.assetId ?? const Uuid().v4(),
        tagName: _tagCtrl.text.trim(),
        category: _category,
        breedType: _breedCtrl.text.trim(),
        status: _status,
        weightKg: _weightCtrl.text.isNotEmpty ? double.tryParse(_weightCtrl.text) : null,
        dateOfBirth: _dateOfBirth,
        healthNotes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
        createdBy: userId,
        createdAt: widget.existing?.createdAt ?? DateTime.now().toUtc(),
      );
      
      await widget.onSaved(asset);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))
      ),
      padding: EdgeInsets.only(
        left: 20, 
        right: 20, 
        top: 20, 
        bottom: MediaQuery.of(context).viewInsets.bottom + 20
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, 
            children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(_isEdit ? 'Edit Animal / Crop' : 'Register Animal / Crop',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),

              // Category
              Row(
                children: AssetCategory.values.map((cat) {
                  final sel = _category == cat;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _category = cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: sel ? const Color(0xFF2D6A4F) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: sel ? const Color(0xFF2D6A4F) : const Color(0xFFD8E8E0)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center, 
                          children: [
                            Icon(cat == AssetCategory.livestock ? Icons.pets : Icons.grass, size: 16,
                                color: sel ? Colors.white : const Color(0xFF52796F)),
                            const SizedBox(width: 6),
                            Text(cat.name.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                                color: sel ? Colors.white : const Color(0xFF52796F))),
                          ]
                        ),
                      ),
                    )
                  );
                }).toList()
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _tagCtrl,
                decoration: const InputDecoration(labelText: 'Tag / Name', hintText: 'e.g. Daisy, Bull-003', prefixIcon: Icon(Icons.label_outline, size: 18)),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null
              ),
              const SizedBox(height: 12),
              
              TextFormField(
                controller: _breedCtrl,
                decoration: const InputDecoration(labelText: 'Breed / Variety', hintText: 'e.g. Friesian, H614D Maize', prefixIcon: Icon(Icons.biotech_outlined, size: 18)),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _weightCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,1}'))],
                      decoration: const InputDecoration(labelText: 'Weight (kg)', hintText: 'e.g. 340', prefixIcon: Icon(Icons.monitor_weight_outlined, size: 18)),
                    )
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDatePicker(
                      label: 'Date of Birth',
                      selected: _dateOfBirth,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      onPicked: (d) => setState(() => _dateOfBirth = d),
                    )
                  ),
                ]
              ),
              const SizedBox(height: 12),

              // Status (edit only)
              if (_isEdit) ...[
                DropdownButtonFormField<AssetStatus>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status', prefixIcon: Icon(Icons.info_outline, size: 18)),
                  items: AssetStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.name.toUpperCase()))).toList(),
                  onChanged: (v) => setState(() => _status = v!),
                ),
                const SizedBox(height: 12),
              ],

              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(labelText: 'Health Notes (optional)', hintText: 'e.g. Vaccinated June 2025', prefixIcon: Icon(Icons.medical_services_outlined, size: 18)),
                maxLines: 2
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F), foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : Text(_isEdit ? 'Save Changes' : 'Register', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              const SizedBox(height: 8),
            ]
          )
        ),
      ),
    );
  }
}