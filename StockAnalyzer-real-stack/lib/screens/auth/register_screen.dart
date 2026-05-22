import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/platform_adaptive/platform_text_field.dart';
import '../../widgets/platform_adaptive/platform_button.dart';
import '../../widgets/platform_adaptive/platform_app_bar.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  Future<void> _handleRegister() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.register(
      _nameController.text,
      _emailController.text,
      _passwordController.text,
    );

    if (success && mounted) {
      // Navigate to home logic is centralized or pop to root
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PlatformAppBar(title: 'Create Account'),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            return SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (auth.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Text(
                        auth.error!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  PlatformTextField(
                    label: 'Name',
                    controller: _nameController,
                    placeholder: 'Enter your name',
                  ),
                  const SizedBox(height: 16),
                  PlatformTextField(
                    label: 'Email',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    placeholder: 'Enter your email',
                  ),
                  const SizedBox(height: 16),
                  PlatformTextField(
                    label: 'Password',
                    controller: _passwordController,
                    obscureText: true,
                    placeholder: 'Choose a password',
                  ),
                  const SizedBox(height: 24),
                  if (auth.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    PlatformButton(
                      label: 'Sign Up',
                      onPressed: _handleRegister,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
