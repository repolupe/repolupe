import 'package:app/gen/strings.g.dart';
import 'package:app/service/account_service.dart';
import 'package:flutter/material.dart';
import 'package:moform/moform.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The step after the choice between a server and this device (which starts the local instance right away).
enum _Mode { remote }

/// Logs in on a Repolupe server, or starts the local instance, as the first account or as another one.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> with Refena {
  bool _loading = false;

  /// `null` while choosing.
  _Mode? _mode;
  String _apiUrl = '';
  String _userNameOrEmail = '';
  String _password = '';

  bool get _canSubmit => !_loading && _apiUrl.trim().isNotEmpty && _userNameOrEmail.trim().isNotEmpty && _password.isNotEmpty;

  Future<void> _login() async {
    await _submit(
      LoginAction(
        apiUrl: _apiUrl,
        userNameOrEmail: _userNameOrEmail,
        password: _password,
      ),
    );
  }

  Future<void> _startLocal() async {
    await _submit(CreateLocalAccountAction());
  }

  Future<void> _submit(AsyncReduxAction<AccountService, AccountState> action) async {
    setState(() {
      _loading = true;
    });
    try {
      await ref.redux(accountProvider).dispatchAsync(action);
    } finally {
      // After a successful login, the home page replaced this one.
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final addingAccount = ModalRoute.of(context)?.canPop ?? false;
    final mode = _mode;
    return PopScope(
      // Back from the login form returns to the choice.
      canPop: mode == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_loading) {
          setState(() {
            _mode = null;
          });
        }
      },
      child: Scaffold(
        appBar: addingAccount || mode != null
            ? AppBar(
                title: addingAccount ? Text(context.t.flutter.setup.addAccount) : null,
                leading: mode == null
                    ? null
                    : BackButton(
                        onPressed: _loading
                            ? null
                            : () {
                                setState(() {
                                  _mode = null;
                                });
                              },
                      ),
              )
            : null,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: mode == null ? 560 : 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!addingAccount) ...[
                      Center(
                        child: Image.asset('assets/logo-512.webp', width: 80, height: 80, semanticLabel: context.t.base.app.logoAlt),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Repolupe',
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        mode == null ? context.t.flutter.setup.intro : context.t.flutter.setup.introRemote,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                    ],
                    if (mode == null) _kinds() else ..._remoteFields(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The big buttons to choose between a server and this device, side by side if there is room.
  Widget _kinds() {
    final remote = _KindCard(
      key: const ValueKey('setup.kind.remote'),
      icon: Icons.cloud_outlined,
      title: context.t.flutter.setup.server,
      description: context.t.flutter.setup.remoteDescription,
      loading: false,
      onTap: _loading
          ? null
          : () {
              setState(() {
                _mode = _Mode.remote;
              });
            },
    );
    final local = _KindCard(
      key: const ValueKey('setup.kind.local'),
      icon: Icons.smartphone_outlined,
      title: context.t.flutter.account.thisDevice,
      description: context.t.flutter.setup.localDescription,
      loading: _loading,
      onTap: _loading ? null : _startLocal,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [remote, const SizedBox(height: 8), local],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: remote),
              const SizedBox(width: 8),
              Expanded(child: local),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _remoteFields() {
    return [
      StringField(
        key: const ValueKey('setup.apiUrl'),
        value: _apiUrl,
        label: context.t.flutter.setup.server,
        hint: 'repolupe.example.com',
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        onChanged: (value) {
          setState(() {
            _apiUrl = value;
          });
        },
      ),
      const SizedBox(height: 16),
      StringField(
        key: const ValueKey('setup.userNameOrEmail'),
        value: _userNameOrEmail,
        label: context.t.base.user.userNameOrEmail,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        onChanged: (value) {
          setState(() {
            _userNameOrEmail = value;
          });
        },
      ),
      const SizedBox(height: 16),
      StringField(
        key: const ValueKey('setup.password'),
        value: _password,
        label: context.t.base.user.password,
        obscureText: true,
        textInputAction: TextInputAction.done,
        onChanged: (value) {
          setState(() {
            _password = value;
          });
        },
        onSubmitted: (_) async {
          if (_canSubmit) {
            await _login();
          }
        },
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _canSubmit ? _login : null,
        icon: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.login),
        label: Text(context.t.base.login.login),
      ),
    ];
  }
}

/// A big button with an icon, a title and a description, like the web's `RepositoryKindDialog`.
class _KindCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  /// Shows a progress indicator instead of the icon.
  final bool loading;

  final VoidCallback? onTap;

  const _KindCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              SizedBox.square(
                dimension: 48,
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(),
                      )
                    : Icon(icon, size: 48, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
