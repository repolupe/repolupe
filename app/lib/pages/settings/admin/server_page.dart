import 'package:app/gen/strings.g.dart';
import 'package:app/service/account_service.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The server of the active account, for admins: its base URL and its version, each copied by tapping it. The local
/// instance has no URL, so it shows `This device`, which is not copied.
class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> with Refena {
  /// `null` until it is loaded.
  ServerDto? _server;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ensureRef((ref) {
      // ignore: discarded_futures
      _load();
    });
  }

  Future<void> _load() async {
    try {
      final server = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiGetServerAction());
      if (mounted) {
        setState(() {
          _server = server;
        });
      }
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.server.page.loadFailed(error: e.userMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.server.page.copied));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final account = context.watch(accountProvider.select((state) => state.active));
    final apiUrl = account?.apiUrl;
    final version = _server?.version;
    return Scaffold(
      appBar: AppBar(title: Text(t.base.admin.server.title)),
      body: ListView(
        padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          ListTile(
            key: const ValueKey('server.baseUrl'),
            leading: const Icon(Icons.link),
            title: Text(t.base.admin.server.page.baseUrl),
            subtitle: Text(apiUrl ?? account?.server ?? ''),
            onTap: apiUrl != null ? () => _copy(apiUrl) : null,
          ),
          ListTile(
            key: const ValueKey('server.version'),
            leading: const Icon(Icons.sell),
            title: Text(t.base.admin.server.page.version),
            subtitle: version != null
                ? Text(version)
                : _loading
                ? const Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
            onTap: version != null ? () => _copy(version) : null,
          ),
        ],
      ),
    );
  }
}
