// lib/screens/sign_detail_screen.dart
//
// Simplified mobile signing:
//   1. Show the document (PDF) for review.
//   2. User draws OR types one signature.
//   3. On "Sign", we fill every field assigned to this signer with the
//      signature value, then submit. The server stamps the PDF (same
//      finalise path as the web).
//
// Requires: pdfx, signature (for the draw pad). See pubspec additions.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:signature/signature.dart';

import '../models/files_models.dart';
import '../services/api_service.dart';
import '../theme/eo_theme.dart';

class SignDetailScreen extends StatefulWidget {
  const SignDetailScreen({super.key, required this.requestId});
  final String requestId;

  @override
  State<SignDetailScreen> createState() => _SignDetailScreenState();
}

class _SignDetailScreenState extends State<SignDetailScreen> {
  final _api = ApiService.instance;

  SignDetail? _detail;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  PdfControllerPinch? _pdfController;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final detail = await _api.signDetail(widget.requestId);
    if (!mounted) return;

    if (detail == null) {
      setState(() {
        _loading = false;
        _error = 'Could not load this request.';
      });
      return;
    }

    // Fetch the PDF bytes (with auth) and build the controller.
    final bytes = await _api.fetchSignPdf(detail.request.previewUrl);
    if (!mounted) return;

    if (bytes != null && bytes.isNotEmpty) {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openData(Uint8List.fromList(bytes)),
      );
    }

    setState(() {
      _detail = detail;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  // ── Signing ────────────────────────────────────────────────────────────────

  Future<void> _startSigning() async {
    final detail = _detail;
    if (detail == null) return;

    if (detail.blockedByOrder) {
      _toast('A previous signer must sign before you.');
      return;
    }

    final result = await showModalBottomSheet<_SignResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: EoColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _SignaturePadSheet(savedSignatures: detail.savedSignatures),
    );

    if (result == null) return;
    await _submit(result);
  }

  Future<void> _submit(_SignResult sig) async {
    final detail = _detail!;
    setState(() => _submitting = true);

    // 1. Fill every field assigned to me with the signature value.
    //    Date fields get today's date; text/initials get the signature too
    //    in this simplified flow (server just needs them non-empty).
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    var allOk = true;
    for (final f in detail.fields) {
      String value;
      switch (f.type) {
        case 'date':
          value = dateStr;
          break;
        case 'text':
        case 'initials':
        case 'signature':
        default:
          value = sig.value;
      }
      final ok = await _api.signFillField(detail.request.requestId, f.id, value);
      if (!ok) allOk = false;
    }

    if (!allOk) {
      if (mounted) {
        setState(() => _submitting = false);
        _toast('Could not save all fields. Please try again.');
      }
      return;
    }

    // 2. Final submit.
    final err = await _api.signSubmit(
      detail.request.requestId,
      signatureData: sig.value,
      signatureType: sig.type,
      saveSignature: sig.save,
      saveSignatureName: 'My Signature',
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (err == null) {
      _toast('Signed. Thank you!');
      Navigator.pop(context, true);
    } else {
      _toast(err);
    }
  }

  Future<void> _decline() async {
    final reasonCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: EoColors.surface,
        title: const Text('Decline to sign'),
        content: TextField(
          controller: reasonCtl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: EoColors.coral,
              foregroundColor: Colors.white,
            ),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    setState(() => _submitting = true);
    final err = await _api.signDecline(widget.requestId, reasonCtl.text.trim());
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err == null) {
      _toast('You declined this request.');
      Navigator.pop(context, true);
    } else {
      _toast(err);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final alreadyDone = detail != null &&
        (detail.request.signerStatus == 'signed' ||
            detail.request.signerStatus == 'declined');

    return Scaffold(
      appBar: AppBar(title: Text(detail?.request.title ?? 'Sign')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: EoColors.deepTeal))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: EoColors.inkSoft)))
              : Column(
                  children: [
                    Expanded(child: _pdfView()),
                    if (detail != null) _bottomBar(detail, alreadyDone),
                  ],
                ),
    );
  }

  Widget _pdfView() {
    if (_pdfController == null) {
      return const Center(
        child: Text('Document preview unavailable.',
            style: TextStyle(color: EoColors.inkSoft)),
      );
    }
    return PdfViewPinch(controller: _pdfController!);
  }

  Widget _bottomBar(SignDetail detail, bool alreadyDone) {
    if (alreadyDone) {
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: EoColors.sandDeep,
          child: Text(
            detail.request.signerStatus == 'signed'
                ? 'You have signed this document.'
                : 'You declined this document.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: EoColors.inkSoft),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: EoColors.surface,
          boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -2))],
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            TextButton(
              onPressed: _submitting ? null : _decline,
              child: const Text('Decline', style: TextStyle(color: EoColors.coral)),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _submitting ? null : _startSigning,
              icon: _submitting
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.draw),
              label: Text(_submitting ? 'Signing…' : 'Sign document'),
              style: ElevatedButton.styleFrom(
                backgroundColor: EoColors.deepTeal,
                foregroundColor: EoColors.onTeal,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Result of the signature pad ──────────────────────────────────────────────

class _SignResult {
  final String value; // base64 data URI (draw) or text (type)
  final String type;  // draw | type
  final bool save;
  _SignResult(this.value, this.type, this.save);
}

// ── Signature pad bottom sheet ───────────────────────────────────────────────

class _SignaturePadSheet extends StatefulWidget {
  const _SignaturePadSheet({required this.savedSignatures});
  final List<SavedSig> savedSignatures;

  @override
  State<_SignaturePadSheet> createState() => _SignaturePadSheetState();
}

class _SignaturePadSheetState extends State<_SignaturePadSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _drawCtl = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  final _typeCtl = TextEditingController();
  bool _save = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _drawCtl.dispose();
    _typeCtl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_tabs.index == 0) {
      // Draw → export PNG → base64 data URI
      if (_drawCtl.isEmpty) {
        _toast('Please draw your signature.');
        return;
      }
      final bytes = await _drawCtl.toPngBytes();
      if (bytes == null) {
        _toast('Could not capture signature.');
        return;
      }
      final dataUri = 'data:image/png;base64,${base64Encode(bytes)}';
      if (!mounted) return;
      Navigator.pop(context, _SignResult(dataUri, 'draw', _save));
    } else {
      final text = _typeCtl.text.trim();
      if (text.isEmpty) {
        _toast('Please type your name.');
        return;
      }
      if (!mounted) return;
      Navigator.pop(context, _SignResult(text, 'type', _save));
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: EoColors.inkSoft.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            TabBar(
              controller: _tabs,
              labelColor: EoColors.deepTeal,
              indicatorColor: EoColors.signalTeal,
              tabs: const [Tab(text: 'Draw'), Tab(text: 'Type')],
            ),
            SizedBox(
              height: 220,
              child: TabBarView(
                controller: _tabs,
                children: [
                  // DRAW
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: EoColors.inkSoft.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Signature(
                              controller: _drawCtl,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _drawCtl.clear(),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Clear'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // TYPE
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _typeCtl,
                          autofocus: false,
                          decoration: InputDecoration(
                            hintText: 'Type your full name',
                            fillColor: EoColors.sand,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Your typed name will be recorded as your signature.',
                          style: TextStyle(color: EoColors.inkSoft, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            CheckboxListTile(
              value: _save,
              onChanged: (v) => setState(() => _save = v ?? false),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Save this signature for next time',
                  style: TextStyle(fontSize: 13.5)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EoColors.deepTeal,
                    foregroundColor: EoColors.onTeal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Apply signature'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
