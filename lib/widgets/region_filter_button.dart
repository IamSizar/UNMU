import 'package:flutter/material.dart';
import 'package:get/get.dart';

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
    final regions = [
      {
        'code': 'GLOBAL',
        'name': 'regionFilter.global'.tr,
        'icon': Icons.public,
      },
      {
        'code': 'US',
        'name': 'regionFilter.us'.tr,
        'icon': Icons.flag,
      },
      {
        'code': 'GCC',
        'name': 'regionFilter.gcc'.tr,
        'icon': Icons.business,
      },
      {
        'code': 'MENA',
        'name': 'regionFilter.mena'.tr,
        'icon': Icons.location_city,
      },
      {
        'code': 'EU',
        'name': 'regionFilter.eu'.tr,
        'icon': Icons.euro,
      },
      {
        'code': 'ASIA',
        'name': 'regionFilter.asia'.tr,
        'icon': Icons.landscape,
      },
      {
        'code': 'CN',
        'name': 'regionFilter.cn'.tr,
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
            color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 12),
          Text(region['name'] as String),
        ],
      ),
    );
  }
}
