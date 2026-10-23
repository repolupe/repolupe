import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/widget/status_chip.dart';
import 'package:flutter/material.dart';

/// What sets a user apart, as small chips: the admin role, and the restrictions an admin set (login disabled, a
/// required password change, repositories read only, a fixed user name and email). Nothing for a plain user.
class UserFlagChips extends StatelessWidget {
  final UserDto user;

  const UserFlagChips({super.key, required this.user});

  /// The label, color and icon of each chip, in the order they are shown.
  static List<(String, Color, IconData)> flags(UserDto user) => [
    if (user.role == UserRole.admin) (t.base.user.roleAdmin, Colors.indigo, Icons.shield),
    if (!user.canLogin) (t.base.admin.users.page.loginDisabled, Colors.red, Icons.block),
    if (user.mustChangePassword) (t.base.admin.users.page.passwordChangeRequired, Colors.orange, Icons.lock_reset),
    if (!user.canManageRepositories) (t.flutter.admin.users.flags.repositoriesReadOnly, Colors.grey, Icons.visibility),
    if (!user.canChangeIdentity) (t.flutter.admin.users.flags.identityFixed, Colors.grey, Icons.person_off),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [for (final (label, color, icon) in flags(user)) StatusChip(label: label, color: color, icon: icon)],
    );
  }
}
