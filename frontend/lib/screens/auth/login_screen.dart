import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../bloc/auth/auth_bloc.dart';
import '../../bloc/auth/auth_event.dart';
import '../../bloc/auth/auth_state.dart';
import '../../components/shared/glass_container.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import '../../utils/app_theme.dart';
import '../../services/api_config.dart';
import '../../components/shared/ambient_scaffold.dart';
import '../../components/shared/chromatic_pulse.dart';
import '../../components/shared/glass_surfaces.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  /// Amber, not the Aurora Pink accent: the DEV affordance should read as
  /// scaffolding rather than as part of the product surface.
  // The local-only sign-in shortcut. Deliberately outside the brand
  // palette: it must never read as a product surface.
  static const Color _devAccent = Color(0xFFFFB300);

  @override
  void initState() {
    super.initState();
    // A failed DEV auto-login errors before this screen is built, so the
    // BlocListener below - which only fires on state *changes* - would never
    // see it. Surface that one already-settled error on first frame.
    final state = context.read<AuthBloc>().state;
    if (state is AuthError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAuthError(state.message);
      });
    }
  }

  void _showAuthError(String message) {
    GlassToast.show(context, message);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() {
    if (context.read<AuthBloc>().state is AuthLoading) return;
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(
        LoginRequested(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthBloc>().state is AuthLoading;
    // The gradient this screen used to hand-roll is now the app's Ambient
    // Field: the same void, drifting, and shared with every other surface —
    // this screen was the prototype for it.
    return AmbientScaffold(
      appearance: Brightness.dark,
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            _showAuthError(state.message);
          }
        },
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassContainer(
                  borderRadius: MapGlass.radiusLg,
                  blur: 20.0,
                  opacity: 0.08,
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // App Logo & Title Instrument
                      Center(
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  MapGlass.radiusMd,
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  width: 1.0,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  MapGlass.radiusMd,
                                ),
                                child: Image.asset(
                                  'assets/Map-My-Friends-Default-1024x1024@1x.png',
                                  width: 80,
                                  height: 80,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'MAP MY FRIENDS',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.montserrat(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Technical Luxury Spatial Instrument',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.openSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w300,
                                color: Colors.white.withValues(alpha: 0.5),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Login Form
                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _usernameController,
                              enabled: !isLoading,
                              style: GoogleFonts.openSans(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Username',
                                labelStyle: GoogleFonts.openSans(
                                  color: Colors.white60,
                                  fontSize: 14,
                                ),
                                prefixIcon: const Icon(
                                  Icons.person_outline,
                                  color: Colors.white60,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.15),
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    MapGlass.radiusMd,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(
                                    color: MapPalette.defaultPin,
                                    width: 1.5,
                                  ), // Evening Indigo
                                  borderRadius: BorderRadius.circular(
                                    MapGlass.radiusMd,
                                  ),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    MapGlass.radiusMd,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.02),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                              textInputAction: TextInputAction.next,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your username';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              enabled: !isLoading,
                              style: GoogleFonts.openSans(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                labelStyle: GoogleFonts.openSans(
                                  color: Colors.white60,
                                  fontSize: 14,
                                ),
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  color: Colors.white60,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.15),
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    MapGlass.radiusMd,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(
                                    color: MapPalette.defaultPin,
                                    width: 1.5,
                                  ), // Evening Indigo
                                  borderRadius: BorderRadius.circular(
                                    MapGlass.radiusMd,
                                  ),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    MapGlass.radiusMd,
                                  ),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.white60,
                                  ),
                                  tooltip: _obscurePassword
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: isLoading
                                      ? null
                                      : () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                ),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.02),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _login(),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your password';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: isLoading
                                    ? null
                                    : () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const ForgotPasswordScreen(),
                                          ),
                                        );
                                      },
                                child: Text(
                                  'Forgot Password?',
                                  style: GoogleFonts.openSans(
                                    color: const Color(
                                      0xFFFF4081,
                                    ), // Aurora Pink accent
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: FilledButton(
                                onPressed: isLoading ? null : _login,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(
                                    0xFF3F51B5,
                                  ), // Evening Indigo
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      MapGlass.radiusMd,
                                    ),
                                  ),
                                ),
                                child: isLoading
                                    ? SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: ChromaticPulse(
                                          colors: PulseIndicator.paletteOf(
                                            context,
                                          ),
                                          borderRadius: 10.0,
                                        ),
                                      )
                                    : Text(
                                        'Sign In',
                                        style: GoogleFonts.montserrat(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // OR CONNECT WITH divider
                      Row(
                        children: [
                          const Expanded(
                            child: Divider(
                              color: Colors.white12,
                              thickness: 1.0,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'OR CONNECT WITH',
                              style: GoogleFonts.montserrat(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white.withValues(alpha: 0.35),
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Divider(
                              color: Colors.white12,
                              thickness: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Social Logins (Google & Apple)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: isLoading
                                  ? null
                                  : () {
                                      context.read<AuthBloc>().add(
                                        const Auth0LoginRequested(
                                          connection: 'google-oauth2',
                                        ),
                                      );
                                    },
                              icon: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white12,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'G',
                                  style: GoogleFonts.montserrat(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              label: Text(
                                'Google',
                                style: GoogleFonts.montserrat(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    MapGlass.radiusMd,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: isLoading
                                  ? null
                                  : () {
                                      context.read<AuthBloc>().add(
                                        const Auth0LoginRequested(
                                          connection: 'apple',
                                        ),
                                      );
                                    },
                              icon: const Icon(
                                Icons.apple,
                                size: 22,
                                color: Colors.white,
                              ),
                              label: Text(
                                'Apple',
                                style: GoogleFonts.montserrat(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    MapGlass.radiusMd,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Unified Auth0 Web Auth Button
                      OutlinedButton(
                        onPressed: isLoading
                            ? null
                            : () {
                                context.read<AuthBloc>().add(
                                  const Auth0LoginRequested(),
                                );
                              },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              MapGlass.radiusMd,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.shield_outlined,
                              size: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Unified Sign In (Auth0)',
                              style: GoogleFonts.montserrat(
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                fontSize: 13,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Local development bypass ──────────────────
                      // Compiled out entirely when devLoginEnabled is
                      // false, which a release build guarantees. The
                      // collection-if folds away with it, so neither the
                      // button nor the credentials reach a shipped binary.
                      if (ApiConfig.devLoginEnabled) ...[
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: isLoading
                              ? null
                              : () {
                                  context.read<AuthBloc>().add(
                                    const DevLoginRequested(),
                                  );
                                },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _devAccent.withValues(alpha: 0.06),
                            side: BorderSide(
                              color: _devAccent.withValues(alpha: 0.4),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                MapGlass.radiusMd,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.developer_mode,
                                size: 18,
                                color: _devAccent,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'DEV Sign In (${ApiConfig.devUsername})',
                                style: GoogleFonts.montserrat(
                                  fontWeight: FontWeight.w600,
                                  color: _devAccent,
                                  fontSize: 13,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Local development only — signs in as the seeded '
                          'user. Requires `make up && make seed`.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.openSans(
                            fontSize: 11,
                            height: 1.4,
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                      ],

                      const SizedBox(height: 28),

                      // Register Link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account? ",
                            style: GoogleFonts.openSans(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 13,
                            ),
                          ),
                          TextButton(
                            onPressed: isLoading
                                ? null
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const RegisterScreen(),
                                      ),
                                    );
                                  },
                            child: Text(
                              'Sign Up',
                              style: GoogleFonts.montserrat(
                                color: MapPalette.accent,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
