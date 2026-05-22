import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../localization/halal_strings.dart';
import '../../providers/language_provider.dart';
import '../../widgets/stock_card.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/ads/banner_ad_widget.dart';
import '../../screens/stock_detail/stock_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  String? _error;
  Timer? _debounceTimer;
  bool _hasText = false;

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final results = await ApiService.searchStocks(query);
      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isSearching = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();

    setState(() {
      _hasText = value.isNotEmpty;
    });

    if (value.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _error = null;
      });
      return;
    }

    if (value.length < 2) {
      setState(() {
        _results = [];
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _search(value);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.watch<LanguageProvider>().isArabic;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isArabic ? HalalStringsAr.searchStocks : HalalStrings.searchStocks,
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: isArabic
                    ? HalalStringsAr.enterTickerOrName
                    : HalalStrings.enterTickerOrName,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _hasText
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _debounceTimer?.cancel();
                          _searchController.clear();
                          setState(() {
                            _hasText = false;
                            _results = [];
                            _isSearching = false;
                            _error = null;
                          });
                        },
                      )
                    : null,
              ),
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) {
                _debounceTimer?.cancel();
                _search(value);
              },
            ),
          ),

          // Results
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _search(_searchController.text),
                          child: Text(
                            isArabic
                                ? HalalStringsAr.retry
                                : HalalStrings.retry,
                          ),
                        ),
                      ],
                    ),
                  )
                : _results.isEmpty
                ? Center(
                    child: Text(
                      _searchController.text.isEmpty
                          ? (isArabic
                                ? HalalStringsAr.enterTickerOrName
                                : HalalStrings.enterTickerOrName)
                          : (isArabic
                                ? HalalStringsAr.noResults
                                : HalalStrings.noResults),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount:
                              !context.watch<AuthProvider>().isPremium &&
                                  _results.length > 5
                              ? 5
                              : _results.length,
                          itemBuilder: (context, index) {
                            final stock = _results[index];
                            return InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StockDetailScreen(
                                      ticker: stock['ticker']?.toString() ?? '',
                                      exchange:
                                          stock['exchange']?.toString() ?? '',
                                    ),
                                  ),
                                );
                              },
                              child: StockCard(stock: stock),
                            );
                          },
                        ),
                      ),
                      if (!context.watch<AuthProvider>().isPremium)
                        const BannerAdWidget(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
