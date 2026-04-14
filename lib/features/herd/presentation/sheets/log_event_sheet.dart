// lib/features/herd/presentation/sheets/log_event_sheet.dart

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../data/models/models.dart';
import '../../../../data/repositories/repositories.dart';
import '../../../../services/image_service.dart';
import '../../../../services/asset_image_widget.dart';
import '../../../../services/session_manager.dart';
import '../../../../shared/widgets/shared_widgets.dart';

class LogEventSheet extends StatefulWidget {
  final Asset asset;
  final HerdRepository repo;
  final VoidCallback onSaved;
  final AssetEvent? existing;

  const LogEventSheet({
    super.key,
    required this.asset,
    required this.repo,
    required this.onSaved,
    this.existing,
  });

  @override
  State<LogEventSheet> createState() => _LogEventSheetState();
}

class _LogEventSheetState extends State<LogEventSheet> {
  late final String _eventId;
  String? _selectedType;
  
  final _notesCtrl      = TextEditingController();
  final _meta1Ctrl      = TextEditingController();
  final _meta2Ctrl      = TextEditingController();
  final _otherLabelCtrl = TextEditingController();
  
  // Phase 1 Extensions
  final _withdrawalDaysCtrl = TextEditingController();
  final _anthelminticClassCtrl = TextEditingController();
  final _routeCtrl = TextEditingController();
  final _nextDueCtrl = TextEditingController();
  final _probableCauseCtrl = TextEditingController();
  final _carcassDisposalCtrl = TextEditingController();
  bool _vetCalled = false;

  final userId = SessionManager.instance.currentUserId;

  DateTime  _recordedAt = DateTime.now();
  DateTime? _endDate;              
  bool _saving = false;
  MilkSession _milkSession = MilkSession.am;
  List<FarmImage> _images = [];

  bool get _isEdit      => widget.existing != null;
  bool get _isLivestock => widget.asset.category == AssetCategory.livestock;

  static const _rangeTypes = {'medication', 'dryingOff', 'isolation', 'injury', 'irrigation', 'weeding'};
  bool get _supportsRange => _rangeTypes.contains(_selectedType);

  static const _livestockTypes = [
    ('deworming',      '💊', 'Deworming'),
    ('vetVisit',       '🏥', 'Vet Visit'),
    ('medication',     '💊', 'Medication'),
    ('hoofTrim',       '🪚', 'Hoof Trim'),
    ('dipping',        '🛁', 'Dipping'),
    ('injury',         '🩹', 'Injury'),
    ('dryingOff',      '🧴', 'Drying Off'),
    ('isolation',      '🚧', 'Isolation'),
    ('mating',         '🔗', 'Mating'),
    ('pregnancyCheck', '🔬', 'Pregnancy Check'),
    ('birth',          '🐣', 'Birth'),
    ('feedChange',     '🌾', 'Feed Change'),
    ('supplement',     '🧪', 'Supplement'),
    ('weightCheck',    '⚖️',  'Weight Check'),
    ('milkLog',        '🥛', 'Milk Log'),
    ('shearing',       '✂️',  'Shearing'),
    ('sold',           '💰', 'Sold'),
    ('deceased',       '🕊️', 'Deceased'),
    ('other',          '📋', 'Other'),
  ];

  static const _cropTypes = [
    ('planting',   '🌱', 'Planting'),
    ('weeding',    '🪴', 'Weeding'),
    ('fertilizer', '🧴', 'Fertilizer'),
    ('pesticide',  '🪣', 'Pesticide'),
    ('irrigation', '💧', 'Irrigation'),
    ('harvest',    '🌾', 'Harvest'),
    ('cropLoss',   '⚠️', 'Crop Loss'),
    ('other',      '📋', 'Other'),
  ];

  List<(String, String, String)> get _types => _isLivestock ? _livestockTypes : _cropTypes;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _eventId = e?.eventId ?? const Uuid().v4();
    
    if (e != null) {
      _selectedType = e.eventType;
      _notesCtrl.text = e.notes ?? '';
      _recordedAt     = e.recordedAt;
      
      if (e.metadata?['date_to'] != null) {
        _endDate = DateTime.tryParse(e.metadata!['date_to'] as String);
      }
      
      final m = e.metadata ?? {};
      switch (e.eventType) {
        case 'weightCheck':
          _meta1Ctrl.text = m['weight_kg']?.toString() ?? '';
        case 'milkLog':
          _meta1Ctrl.text = m['litres']?.toString() ?? '';
          final s = m['session'] as String?;
          if (s != null) {
            _milkSession = MilkSession.values.firstWhere((v) => v.name == s, orElse: () => MilkSession.am);
          }
        case 'deworming':
        case 'medication':
        case 'dryingOff':
        case 'isolation':
          _meta1Ctrl.text = m['drug']?.toString() ?? '';
          _meta2Ctrl.text = m['dose']?.toString() ?? '';
          _withdrawalDaysCtrl.text = m['withdrawal_days']?.toString() ?? '';
          _anthelminticClassCtrl.text = m['anthelmintic_class']?.toString() ?? '';
          _routeCtrl.text = m['route']?.toString() ?? '';
          _nextDueCtrl.text = m['next_due_date']?.toString() ?? '';
        case 'mating':
          _meta1Ctrl.text = m['sire']?.toString() ?? '';
        case 'birth':
          _meta1Ctrl.text = m['offspring_count']?.toString() ?? '';
          _meta2Ctrl.text = m['offspring_tags']?.toString() ?? '';
        case 'feedChange':
          _meta1Ctrl.text = m['feed_type']?.toString() ?? '';
        case 'harvest':
          _meta1Ctrl.text = m['yield']?.toString() ?? '';
          _meta2Ctrl.text = m['unit']?.toString() ?? '';
        case 'fertilizer':
        case 'pesticide':
          _meta1Ctrl.text = m['product']?.toString() ?? '';
          _meta2Ctrl.text = m['quantity']?.toString() ?? '';
        case 'sold':
          _meta1Ctrl.text = m['buyer']?.toString() ?? '';
          _meta2Ctrl.text = m['amount_kes']?.toString() ?? '';
        case 'deceased':
        case 'injury':
          _probableCauseCtrl.text = m['probable_cause']?.toString() ?? '';
          _carcassDisposalCtrl.text = m['carcass_disposal']?.toString() ?? '';
          _vetCalled = m['vet_called'] == true;
        case 'other':
          _otherLabelCtrl.text = m['activity']?.toString() ?? '';
      }
      
      ImageService.instance
          .getImages(entityType: ImageEntityType.assetEvent, entityId: _eventId)
          .then((imgs) { if (mounted) setState(() => _images = imgs); });
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _meta1Ctrl.dispose();
    _meta2Ctrl.dispose();
    _otherLabelCtrl.dispose();
    _withdrawalDaysCtrl.dispose();
    _anthelminticClassCtrl.dispose();
    _routeCtrl.dispose();
    _nextDueCtrl.dispose();
    _probableCauseCtrl.dispose();
    _carcassDisposalCtrl.dispose();
    super.dispose();
  }

  Widget _metaFields() {
    switch (_selectedType) {
      case 'weightCheck':
        return _MetaField(ctrl: _meta1Ctrl, label: 'Weight (kg)', hint: 'e.g. 340', keyboard: TextInputType.number);
      case 'milkLog':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _MetaField(ctrl: _meta1Ctrl, label: 'Litres collected', hint: 'e.g. 12.5', keyboard: TextInputType.number),
          const SizedBox(height: 12),
          const Text('Session', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2D6A4F), letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Row(children: MilkSession.values.map((s) {
            final sel = _milkSession == s;
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _milkSession = s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF2D6A4F) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sel ? const Color(0xFF2D6A4F) : const Color(0xFFD8E8E0)),
                ),
                child: Center(child: Text(s.name.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                    color: sel ? Colors.white : const Color(0xFF52796F)))),
              ),
            ));
          }).toList()),
        ]);
      case 'deworming':
      case 'medication':
      case 'dryingOff':
      case 'isolation':
        return Column(children: [
          _MetaField(ctrl: _meta1Ctrl, label: 'Drug / Product name', hint: 'e.g. Ivermectin'),
          const SizedBox(height: 12),
          _MetaField(ctrl: _meta2Ctrl, label: 'Dose / Quantity', hint: 'e.g. 5ml'),
          if (_selectedType == 'deworming' || _selectedType == 'medication') ...[
            const SizedBox(height: 12),
            _MetaField(ctrl: _anthelminticClassCtrl, label: 'Anthelmintic Class', hint: 'e.g. BZ, LEV, ML'),
            const SizedBox(height: 12),
            _MetaField(ctrl: _routeCtrl, label: 'Route', hint: 'e.g. Oral, Injectable'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _MetaField(ctrl: _withdrawalDaysCtrl, label: 'Withdrawal (Days)', hint: 'e.g. 14', keyboard: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: _MetaField(ctrl: _nextDueCtrl, label: 'Next Due (YYYY-MM-DD)', hint: 'Optional')),
            ]),
          ]
        ]);
      case 'mating':
        return _MetaField(ctrl: _meta1Ctrl, label: 'Sire / Bull ID or Name', hint: 'e.g. Bull-007');
      case 'birth':
        return Column(children: [
          _MetaField(ctrl: _meta1Ctrl, label: 'Number of offspring', hint: 'e.g. 1', keyboard: TextInputType.number),
          const SizedBox(height: 12),
          _MetaField(ctrl: _meta2Ctrl, label: 'Offspring tag(s)', hint: 'e.g. Calf-001'),
        ]);
      case 'feedChange':
        return _MetaField(ctrl: _meta1Ctrl, label: 'New feed type', hint: 'e.g. Silage + Dairy Meal');
      case 'harvest':
        return Column(children: [
          _MetaField(ctrl: _meta1Ctrl, label: 'Yield quantity', hint: 'e.g. 40'),
          const SizedBox(height: 12),
          _MetaField(ctrl: _meta2Ctrl, label: 'Unit', hint: 'e.g. bags, kg, crates'),
        ]);
      case 'fertilizer':
      case 'pesticide':
        return Column(children: [
          _MetaField(ctrl: _meta1Ctrl, label: 'Product name', hint: 'e.g. CAN, Dithane M-45'),
          const SizedBox(height: 12),
          _MetaField(ctrl: _meta2Ctrl, label: 'Quantity applied', hint: 'e.g. 50kg, 2L'),
        ]);
      case 'sold':
        return Column(children: [
          _MetaField(ctrl: _meta1Ctrl, label: 'Buyer name', hint: 'e.g. Kamau Dairy'),
          const SizedBox(height: 12),
          _MetaField(ctrl: _meta2Ctrl, label: 'Sale amount (KES)', hint: 'e.g. 85000', keyboard: TextInputType.number),
        ]);
      case 'deceased':
      case 'injury':
        return Column(children: [
          _MetaField(ctrl: _probableCauseCtrl, label: 'Probable Cause / Diagnosis', hint: 'e.g. Pneumonia, Predator'),
          const SizedBox(height: 12),
          _MetaField(ctrl: _carcassDisposalCtrl, label: 'Carcass Disposal Method', hint: 'e.g. Buried, Burned'),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Vet Called?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF52796F))),
            value: _vetCalled,
            activeThumbColor: const Color(0xFF2D6A4F),
            onChanged: (v) => setState(() => _vetCalled = v),
          ),
        ]);
      case 'other':
        return _MetaField(ctrl: _otherLabelCtrl, label: 'Activity description', hint: 'e.g. Hand milking, Shearing');
      default:
        return const SizedBox.shrink();
    }
  }

  Map<String, dynamic> _buildMetadata() {
    final m = <String, dynamic>{};
    if (_endDate != null && _supportsRange) {
      m['date_to'] = _endDate!.toIso8601String().substring(0, 10);
    }
    switch (_selectedType) {
      case 'weightCheck':
        if (_meta1Ctrl.text.isNotEmpty) m['weight_kg'] = double.tryParse(_meta1Ctrl.text);
      case 'milkLog':
        if (_meta1Ctrl.text.isNotEmpty) m['litres'] = double.tryParse(_meta1Ctrl.text);
        m['session'] = _milkSession.name;
      case 'deworming':
      case 'medication':
      case 'dryingOff':
      case 'isolation':
        if (_meta1Ctrl.text.isNotEmpty) m['drug'] = _meta1Ctrl.text.trim();
        if (_meta2Ctrl.text.isNotEmpty) m['dose'] = _meta2Ctrl.text.trim();
        if (_selectedType == 'deworming' || _selectedType == 'medication') {
          if (_withdrawalDaysCtrl.text.isNotEmpty) {
            final days = int.tryParse(_withdrawalDaysCtrl.text);
            m['withdrawal_days'] = days;
            if (days != null) {
              m['withdrawal_end_date'] = _recordedAt.add(Duration(days: days)).toIso8601String().substring(0, 10);
            }
          }
          if (_anthelminticClassCtrl.text.isNotEmpty) m['anthelmintic_class'] = _anthelminticClassCtrl.text.trim();
          if (_routeCtrl.text.isNotEmpty) m['route'] = _routeCtrl.text.trim();
          if (_nextDueCtrl.text.isNotEmpty) m['next_due_date'] = _nextDueCtrl.text.trim();
        }
      case 'mating':
        if (_meta1Ctrl.text.isNotEmpty) m['sire'] = _meta1Ctrl.text.trim();
      case 'birth':
        if (_meta1Ctrl.text.isNotEmpty) m['offspring_count'] = int.tryParse(_meta1Ctrl.text);
        if (_meta2Ctrl.text.isNotEmpty) m['offspring_tags'] = _meta2Ctrl.text.trim();
      case 'feedChange':
        if (_meta1Ctrl.text.isNotEmpty) m['feed_type'] = _meta1Ctrl.text.trim();
      case 'harvest':
        if (_meta1Ctrl.text.isNotEmpty) m['yield'] = _meta1Ctrl.text.trim();
        if (_meta2Ctrl.text.isNotEmpty) m['unit'] = _meta2Ctrl.text.trim();
      case 'fertilizer':
      case 'pesticide':
        if (_meta1Ctrl.text.isNotEmpty) m['product'] = _meta1Ctrl.text.trim();
        if (_meta2Ctrl.text.isNotEmpty) m['quantity'] = _meta2Ctrl.text.trim();
      case 'sold':
        if (_meta1Ctrl.text.isNotEmpty) m['buyer'] = _meta1Ctrl.text.trim();
        if (_meta2Ctrl.text.isNotEmpty) m['amount_kes'] = double.tryParse(_meta2Ctrl.text);
      case 'deceased':
      case 'injury':
        if (_probableCauseCtrl.text.isNotEmpty) m['probable_cause'] = _probableCauseCtrl.text.trim();
        if (_carcassDisposalCtrl.text.isNotEmpty) m['carcass_disposal'] = _carcassDisposalCtrl.text.trim();
        m['vet_called'] = _vetCalled;
      case 'other':
        if (_otherLabelCtrl.text.isNotEmpty) m['activity'] = _otherLabelCtrl.text.trim();
    }
    return m;
  }

  Future<void> _pickImage(ImageSource source) async {
    final img = await ImageService.instance.pickAndSave(
      entityType: ImageEntityType.assetEvent,
      entityId:   _eventId,
      createdBy:  userId,
      source:     source,
    );
    if (img != null && mounted) setState(() => _images = [..._images, img]);
  }

  Future<void> _deleteImage(FarmImage img) async {
    await ImageService.instance.delete(img);
    if (mounted) setState(() => _images = _images.where((i) => i.imageId != img.imageId).toList());
  }

  Future<void> _save() async {
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an activity type')));
      return;
    }
    setState(() => _saving = true);
    
    try {
      final event = AssetEvent(
        eventId:   _eventId,
        assetId:   widget.asset.assetId,
        eventType: _selectedType!,
        notes:     _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
        metadata:  _buildMetadata().isNotEmpty ? _buildMetadata() : null,
        recordedAt: _recordedAt,
        createdBy:  userId,
        createdAt:  widget.existing?.createdAt ?? DateTime.now(),
      );

      if (_isEdit) {
        await widget.repo.updateAssetEvent(event);
      } else {
        if (_selectedType == 'milkLog' && _meta1Ctrl.text.isNotEmpty) {
          final litres = double.tryParse(_meta1Ctrl.text) ?? 0;
          if (litres > 0) {
            await widget.repo.saveMilkLog(MilkLog(
              logId:      const Uuid().v4(),
              assetId:    widget.asset.assetId,
              litres:     litres,
              session:    _milkSession,
              recordedAt: _recordedAt,
              notes:      _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
              createdBy:  userId,
              createdAt:  DateTime.now(),
            ));
          }
        }
        await widget.repo.saveAssetEvent(event);
      }
      if (mounted) { Navigator.pop(context); widget.onSaved(); }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, 
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(_isEdit ? 'Edit Activity' : 'Log Activity',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(widget.asset.tagName, style: const TextStyle(color: Color(0xFF2D6A4F), fontWeight: FontWeight.w600)),
              ]
            ),
            const SizedBox(height: 20),

            // Event type grid
            const SectionLabel('Activity Type'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _types.map((t) {
                final (type, emoji, label) = t;
                final sel = _selectedType == type;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedType = type;
                    _meta1Ctrl.clear(); _meta2Ctrl.clear();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFF2D6A4F) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? const Color(0xFF2D6A4F) : const Color(0xFFD8E8E0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min, 
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : const Color(0xFF52796F))),
                      ]
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            if (_selectedType != null) ...[
              _metaFields(),
              const SizedBox(height: 14),
            ],

            // Date picker(s)
            AppDatePicker(
              label: 'Start date', 
              selected: _recordedAt, 
              onPicked: (d) => setState(() => _recordedAt = d)
            ),
            if (_supportsRange) ...[ 
              const SizedBox(height: 10),
              AppDatePicker(
                label: 'End date (optional)', 
                selected: _endDate, 
                onPicked: (d) => setState(() => _endDate = d),
              ),
              if (_endDate != null)
                 Align(
                   alignment: Alignment.centerRight,
                   child: TextButton(
                     onPressed: () => setState(() => _endDate = null),
                     child: const Text('Clear End Date', style: TextStyle(fontSize: 12)),
                   ),
                 )
            ],
            const SizedBox(height: 14),

            // Notes
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Any extra details...',
                prefixIcon: Icon(Icons.notes_outlined, size: 18),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            // Photos
            const SectionLabel('Photo'),
            const SizedBox(height: 10),
            AssetImageStrip(
              images:    _images,
              maxImages: 1,
              onAdd:     (source) => _pickImage(source),
              onDelete:  (img)    => _deleteImage(img),
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
                  : Text(_isEdit ? 'Save Changes' : 'Save Activity',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            const SizedBox(height: 8),
          ]
        )
      ),
    );
  }
}

class _MetaField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final TextInputType keyboard;
  const _MetaField({required this.ctrl, required this.label, required this.hint, this.keyboard = TextInputType.text});
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: ctrl,
    keyboardType: keyboard,
    decoration: InputDecoration(labelText: label, hintText: hint),
  );
}