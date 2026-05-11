import 'package:flutter/material.dart';
import '../../core/api_client.dart';

class LoginScreen extends StatefulWidget {
  final ApiClient api;
  final void Function(String token) onLogin;
  const LoginScreen({super.key, required this.api, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _registering = false;
  bool _loading = false;

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      Map<String, dynamic> res;
      if (_registering) {
        res = await widget.api.post('/api/v1/auth/register', {
          'email': _email.text,
          'display_name': _name.text,
          'password': _password.text,
        });
      } else {
        res = await widget.api.post('/api/v1/auth/login', {
          'email': _email.text,
          'password': _password.text,
        });
      }
      widget.onLogin(res['token'] as String);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_registering ? "Registration" : "Login"} failed')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircleAvatar(
                radius: 40,
                backgroundColor: Color(0xFF00E5FF),
                child: Icon(Icons.smart_toy, size: 40, color: Colors.black),
              ),
              const SizedBox(height: 16),
              const Text('Jarvis', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_registering ? 'Create your account' : 'Welcome back', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 32),
              if (_registering)
                TextField(
                  controller: _name,
                  decoration: _input('Display Name', Icons.person),
                  style: const TextStyle(color: Colors.white),
                ),
              if (_registering) const SizedBox(height: 12),
              TextField(
                controller: _email,
                decoration: _input('Email', Icons.email),
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                decoration: _input('Password', Icons.lock),
                obscureText: true,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(_registering ? 'Register' : 'Login', style: const TextStyle(fontSize: 16, color: Colors.black)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _registering = !_registering),
                child: Text(
                  _registering ? 'Already have an account? Login' : "Don't have an account? Register",
                  style: const TextStyle(color: Color(0xFF00E5FF)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _input(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      prefixIcon: Icon(icon, color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }
}
