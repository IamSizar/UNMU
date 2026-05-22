import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../utils/platform_utils.dart';

class PlatformTextField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final String? errorText;

  const PlatformTextField({
    super.key,
    required this.label,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.placeholder,
    this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformUtils.isIOS) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
            child: Text(
              label,
              style: const TextStyle(
                color: CupertinoColors.systemGrey,
                fontSize: 14,
              ),
            ),
          ),
          CupertinoTextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            placeholder: placeholder,
            onChanged: onChanged,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey6,
              borderRadius: BorderRadius.circular(8),
              border: errorText != null
                  ? Border.all(color: CupertinoColors.systemRed)
                  : null,
            ),
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, top: 4),
              child: Text(
                errorText!,
                style: const TextStyle(
                  color: CupertinoColors.systemRed,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      );
    } else {
      return TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: placeholder,
          errorText: errorText,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      );
    }
  }
}
