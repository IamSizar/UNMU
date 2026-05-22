import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../utils/platform_utils.dart';

class PlatformSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const PlatformSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformUtils.isIOS) {
      // iOS: Use Cupertino switch
      return CupertinoSwitch(value: value, onChanged: onChanged);
    } else {
      // Android: Use Material switch
      return Switch(value: value, onChanged: onChanged);
    }
  }
}
