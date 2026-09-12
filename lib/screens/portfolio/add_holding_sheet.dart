import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/portfolio_controller.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/api_service.dart';

/// Bottom sheet: search a stock, enter shares + avg buy price, save.
/// Extracted from portfolio_screen.dart to keep that file under the
/// project's 500-line-per-file guideline.
class AddHoldingSheet extends StatefulWidget {
  const AddHoldingSheet({super.key, required this.token});

  final String token;

  @override
  State<AddHoldingSheet> createState() => _AddHoldingSheetState();
}

class _AddHoldingSheetState extends State<AddHoldingSheet> {
  final _searchController = TextEditingController();
  final _sharesController = TextEditingController();
  final _priceController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selected;
  bool _saving = false;
  bool _searching = false;
  String? _saveError;
  Timer? _debounce;
  int _searchRequestId = 0;

  bool get _isValid {
    if (_selected == null) return false;
    final shares = double.tryParse(_sharesController.text);
    final price = double.tryParse(_priceController.text);
    return shares != null && shares > 0 && price != null && price > 0;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _sharesController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    final requestId = ++_searchRequestId;
    setState(() => _searching = true);
    final results = await ApiService.searchStocks(query.trim());
    // A faster later keystroke may have already started a newer request —
    // drop this response if it's not the most recent one, so a slow query
    // for "A" can't overwrite the results for "AAPL" typed right after it.
    if (!mounted || requestId != _searchRequestId) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  Future<void> _save() async {
    if (!_isValid) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final ok = await Get.find<PortfolioController>().addHolding(
      widget.token,
      (_selected!['id'] as num).toInt(),
      double.parse(_sharesController.text),
      double.parse(_priceController.text),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _saveError = 'portfolio.errorSaving'.tr;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'portfolio.addHolding'.tr,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                if (_selected == null)
                  _SearchStep(
                    palette: palette,
                    controller: _searchController,
                    searching: _searching,
                    results: _results,
                    onChanged: _onSearchChanged,
                    onSelect: (s) => setState(() {
                      _selected = s;
                      _results = [];
                    }),
                  )
                else
                  _DetailsStep(
                    palette: palette,
                    selected: _selected!,
                    sharesController: _sharesController,
                    priceController: _priceController,
                    isValid: _isValid,
                    saving: _saving,
                    saveError: _saveError,
                    onClearSelection: () => setState(() => _selected = null),
                    onFieldChanged: () => setState(() {}),
                    onSave: _save,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Step 1: search for a stock and pick one from the results.
class _SearchStep extends StatelessWidget {
  const _SearchStep({
    required this.palette,
    required this.controller,
    required this.searching,
    required this.results,
    required this.onChanged,
    required this.onSelect,
  });

  final SocialPalette palette;
  final TextEditingController controller;
  final bool searching;
  final List<Map<String, dynamic>> results;
  final ValueChanged<String> onChanged;
  final ValueChanged<Map<String, dynamic>> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          style: TextStyle(color: palette.textPrimary),
          decoration: InputDecoration(
            hintText: 'portfolio.searchHint'.tr,
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: palette.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: palette.border),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (searching) const LinearProgressIndicator(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: results.length,
            itemBuilder: (_, i) {
              final s = results[i];
              return ListTile(
                title: Text(
                  '${s['ticker'] ?? ''} — ${s['name'] ?? ''}',
                  style: TextStyle(color: palette.textPrimary),
                ),
                onTap: () => onSelect(s),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Step 2: enter shares + average buy price for the selected stock.
class _DetailsStep extends StatelessWidget {
  const _DetailsStep({
    required this.palette,
    required this.selected,
    required this.sharesController,
    required this.priceController,
    required this.isValid,
    required this.saving,
    required this.saveError,
    required this.onClearSelection,
    required this.onFieldChanged,
    required this.onSave,
  });

  final SocialPalette palette;
  final Map<String, dynamic> selected;
  final TextEditingController sharesController;
  final TextEditingController priceController;
  final bool isValid;
  final bool saving;
  final String? saveError;
  final VoidCallback onClearSelection;
  final VoidCallback onFieldChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          tileColor: palette.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(
            '${selected['ticker'] ?? ''} — ${selected['name'] ?? ''}',
            style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: onClearSelection,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: sharesController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => onFieldChanged(),
          style: TextStyle(color: palette.textPrimary),
          decoration: InputDecoration(
            labelText: 'portfolio.shares'.tr,
            filled: true,
            fillColor: palette.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: palette.border),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: priceController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onChanged: (_) => onFieldChanged(),
          style: TextStyle(color: palette.textPrimary),
          decoration: InputDecoration(
            labelText: 'portfolio.avgBuyPrice'.tr,
            prefixText: '\$ ',
            filled: true,
            fillColor: palette.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: palette.border),
            ),
          ),
        ),
        if (saveError != null) ...[
          const SizedBox(height: 8),
          Text(saveError!, style: const TextStyle(color: SocialTokens.down, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: isValid && !saving ? onSave : null,
          child: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('portfolio.save'.tr),
        ),
      ],
    );
  }
}
