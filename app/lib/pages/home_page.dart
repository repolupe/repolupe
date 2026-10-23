import 'package:app/pages/change_password_page.dart';
import 'package:app/pages/chat_page.dart';
import 'package:app/service/me_service.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// The root page of the active account: the chat, or the page to change the password while the user must change
/// it (the API rejects everything else until then, see `UserDto.mustChangePassword`). The pages above it are
/// closed when that starts, since their requests fail now.
class HomePage extends StatelessWidget {
  /// The repositories the new chat reads, see [ChatPage.repositoryIds].
  final List<UuidValue>? repositoryIds;

  const HomePage({super.key, this.repositoryIds});

  @override
  Widget build(BuildContext context) {
    final mustChangePassword = context.watch(
      meProvider.select((user) => user?.mustChangePassword ?? false),
      listener: (prev, next) {
        if ((next?.mustChangePassword ?? false) && !(prev?.mustChangePassword ?? false)) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
    );
    return mustChangePassword ? const ChangePasswordPage() : ChatPage(repositoryIds: repositoryIds);
  }
}
