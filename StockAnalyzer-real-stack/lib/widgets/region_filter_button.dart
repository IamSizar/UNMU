import 'package:flutter/material.dart';

import '../localization/halal_strings.dart';
import '../providers/language_provider.dart';
import 'package:provider/provider.dart';

class RegionFilterButton extends StatelessWidget {
  final Function(String) onRegionSelected;
  final String? selectedRegion;

  const RegionFilterButton({
    super.key,
    required this.onRegionSelected,
    this.selectedRegion,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = context.watch<LanguageProvider>().isArabic;

    final regions = [
      {
        'code': 'GLOBAL',
        'name': isArabic
            ? HalalStringsAr.regionGlobal
            : HalalStrings.regionGlobal,
        'icon': Icons.public,
      },
      {
        'code': 'US',
        'name': isArabic ? HalalStringsAr.regionUS : HalalStrings.regionUS,
        'icon': Icons.flag,
      },
      {
        'code': 'GCC',
        'name': isArabic ? HalalStringsAr.regionGCC : HalalStrings.regionGCC,
        'icon': Icons.business,
      },
      {
        'code': 'MENA',
        'name': isArabic ? HalalStringsAr.regionMENA : HalalStrings.regionMENA,
        'icon': Icons.location_city,
      },
      {
        'code': 'EU',
        'name': isArabic ? HalalStringsAr.regionEU : HalalStrings.regionEU,
        'icon': Icons.euro,
      },
      {
        'code': 'ASIA',
        'name': isArabic ? HalalStringsAr.regionASIA : HalalStrings.regionASIA,
        'icon': Icons.landscape,
      },
      {
        'code': 'CN',
        'name': isArabic ? HalalStringsAr.regionCN : HalalStrings.regionCN,
        'icon': Icons.apartment,
      },
    ];

    // Find icon for selected region
    final selectedRegionItem = regions.firstWhere(
      (r) => r['code'] == (selectedRegion ?? 'GLOBAL'),
      orElse: () => regions[0],
    );

    return PopupMenuButton<String>(
      onSelected: onRegionSelected,
      icon: Icon(
        selectedRegionItem['icon'] as IconData,
        color: Theme.of(context).primaryColor,
      ),
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) {
        return [
          _buildMenuItem(context, regions[0]),
          _buildMenuItem(context, regions[1]),
          _buildMenuItem(context, regions[2]),
          const PopupMenuDivider(),
          _buildMenuItem(context, regions[3]),
          _buildMenuItem(context, regions[4]),
          _buildMenuItem(context, regions[5]),
          _buildMenuItem(context, regions[6]),
        ];
      },
    );
  }

  PopupMenuItem<String> _buildMenuItem(
    BuildContext context,
    Map<String, dynamic> region,
  ) {
    return PopupMenuItem<String>(
      value: region['code'] as String,
      child: Row(
        children: [
          Icon(
            region['icon'] as IconData,
            size: 20,
            color: Theme.of(context).iconTheme.color?.withOpacity(0.7),
          ),
          const SizedBox(width: 12),
          Text(region['name'] as String),
        ],
      ),
    );
  }
}
