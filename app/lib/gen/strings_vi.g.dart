///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';

import 'strings.g.dart';

// Path: <root>
class TranslationsVi extends Translations with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsVi({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
    TranslationMetadata<AppLocale, Translations>? meta,
  }) : assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
       _meta =
           meta ??
           TranslationMetadata(
             locale: AppLocale.vi,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver);

  /// Metadata for the translations of <vi>.
  final TranslationMetadata<AppLocale, Translations> _meta;
  @override
  TranslationMetadata<AppLocale, Translations> get $meta => _meta;

  late final TranslationsVi _root = this; // ignore: unused_field

  @override
  TranslationsVi $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsVi(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$base$vi base = _Translations$base$vi._(_root);
  @override
  late final _Translations$flutter$vi flutter = _Translations$flutter$vi._(_root);
}

// Path: base
class _Translations$base$vi extends Translations$base$en {
  _Translations$base$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$base$common$vi common = _Translations$base$common$vi._(_root);
  @override
  late final _Translations$base$errors$vi errors = _Translations$base$errors$vi._(_root);
  @override
  late final _Translations$base$status$vi status = _Translations$base$status$vi._(_root);
  @override
  late final _Translations$base$user$vi user = _Translations$base$user$vi._(_root);
  @override
  late final _Translations$base$app$vi app = _Translations$base$app$vi._(_root);
  @override
  late final _Translations$base$login$vi login = _Translations$base$login$vi._(_root);
  @override
  late final _Translations$base$chat$vi chat = _Translations$base$chat$vi._(_root);
  @override
  late final _Translations$base$settings$vi settings = _Translations$base$settings$vi._(_root);
  @override
  late final _Translations$base$repositories$vi repositories = _Translations$base$repositories$vi._(_root);
  @override
  late final _Translations$base$documents$vi documents = _Translations$base$documents$vi._(_root);
  @override
  late final _Translations$base$mcpServers$vi mcpServers = _Translations$base$mcpServers$vi._(_root);
  @override
  late final _Translations$base$admin$vi admin = _Translations$base$admin$vi._(_root);
}

// Path: flutter
class _Translations$flutter$vi extends Translations$flutter$en {
  _Translations$flutter$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$common$vi common = _Translations$flutter$common$vi._(_root);
  @override
  late final _Translations$flutter$setup$vi setup = _Translations$flutter$setup$vi._(_root);
  @override
  late final _Translations$flutter$account$vi account = _Translations$flutter$account$vi._(_root);
  @override
  late final _Translations$flutter$chat$vi chat = _Translations$flutter$chat$vi._(_root);
  @override
  late final _Translations$flutter$settings$vi settings = _Translations$flutter$settings$vi._(_root);
  @override
  late final _Translations$flutter$validation$vi validation = _Translations$flutter$validation$vi._(_root);
  @override
  late final _Translations$flutter$repositories$vi repositories = _Translations$flutter$repositories$vi._(_root);
  @override
  late final _Translations$flutter$mcpServers$vi mcpServers = _Translations$flutter$mcpServers$vi._(_root);
  @override
  late final _Translations$flutter$documents$vi documents = _Translations$flutter$documents$vi._(_root);
  @override
  late final _Translations$flutter$format$vi format = _Translations$flutter$format$vi._(_root);
  @override
  late final _Translations$flutter$admin$vi admin = _Translations$flutter$admin$vi._(_root);
}

// Path: base.common
class _Translations$base$common$vi extends Translations$base$common$en {
  _Translations$base$common$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get save => 'Lưu';
  @override
  String get cancel => 'Hủy';
  @override
  String get delete => 'Xóa';
  @override
  String get close => 'Đóng';
  @override
  String get edit => 'Chỉnh sửa';
  @override
  String get retry => 'Thử lại';
  @override
  String get search => 'Tìm kiếm';
  @override
  String get refresh => 'Làm mới';
  @override
  String get download => 'Tải xuống';
  @override
  String get name => 'Tên';
  @override
  String get model => 'Mô hình';
  @override
  String get status => 'Trạng thái';
  @override
  String get error => 'Lỗi';
  @override
  String get unknownError => 'Lỗi không xác định';
  @override
  String get required => 'Bắt buộc.';
  @override
  String get loading => 'Đang tải...';
  @override
  String get actions => 'Thao tác';
  @override
  String get kDefault => 'Mặc định';
  @override
  String get added => 'Đã thêm';
  @override
  String get repository => 'Kho lưu trữ';
  @override
  String get input => 'Đầu vào';
  @override
  String get output => 'Đầu ra';
  @override
  String get missingName => 'Thiếu tên';
  @override
  String nameTooLong({required Object max}) => 'Tên tối đa ${max} ký tự';
}

// Path: base.errors
class _Translations$base$errors$vi extends Translations$base$errors$en {
  _Translations$base$errors$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String invalidResponse({required Object status}) => 'Máy chủ trả về phản hồi không mong đợi (${status}).';
  @override
  String get unreachable => 'Không thể kết nối đến máy chủ.';
  @override
  String get internalError => 'Đã xảy ra lỗi trên máy chủ.';
  @override
  String get validationError => 'Yêu cầu không hợp lệ.';
  @override
  String get unsupportedMediaType => 'Yêu cầu có định dạng không được hỗ trợ.';
  @override
  String get unauthorized => 'Bạn chưa đăng nhập.';
  @override
  String get forbidden => 'Bạn không có quyền thực hiện thao tác này.';
  @override
  String get notFound => 'Không tìm thấy, có thể đã bị xóa.';
  @override
  String get conflict => 'Dữ liệu đã bị thay đổi cùng lúc, vui lòng thử lại.';
  @override
  String get rateLimited => 'Quá nhiều yêu cầu, vui lòng thử lại sau.';
  @override
  String get userNameTaken => 'Tên người dùng này đã được sử dụng.';
  @override
  String get emailTaken => 'Email này đã được sử dụng.';
  @override
  String get nameTaken => 'Tên này đã được sử dụng.';
  @override
  String get repoNotFound => 'Không tìm thấy kho lưu trữ trên máy chủ từ xa.';
  @override
  String get branchNotFound => 'Không tìm thấy nhánh trên máy chủ từ xa.';
  @override
  String get authFailed => 'Thông tin xác thực bị từ chối, hãy kiểm tra token truy cập hoặc khóa API.';
  @override
  String get tokenRequired => 'Host đã thay đổi nên không thể giữ lại token hoặc khóa API đã lưu. Hãy nhập giá trị mới hoặc xóa nó.';
  @override
  String get remoteUnreachable => 'Không thể kết nối đến máy chủ từ xa, hoặc máy chủ phản hồi lỗi.';
  @override
  String get unknownRepository => 'Một kho lưu trữ không còn tồn tại.';
  @override
  String get unknownMcpServer => 'Một máy chủ MCP không còn tồn tại.';
  @override
  String get unknownUser => 'Không có người dùng nào với tên người dùng hoặc email này.';
  @override
  String get generationInProgress => 'Một câu trả lời đang được tạo trong đoạn chat này.';
  @override
  String get notRetryable => 'Chỉ có thể thử lại câu trả lời thất bại hoặc đã bị hủy ở cuối đoạn chat.';
  @override
  String get wrongPassword => 'Mật khẩu hiện tại không đúng.';
  @override
  String get samePassword => 'Mật khẩu mới phải khác mật khẩu hiện tại.';
  @override
  String get passwordChangeRequired => 'Bạn phải đổi mật khẩu trước.';
  @override
  String get unknownModel => 'Mô hình không còn khả dụng.';
  @override
  String get noModelConfigured => 'Chưa có mô hình ngôn ngữ nào được cấu hình, hãy nhờ quản trị viên thêm một mô hình.';
  @override
  String get unavailable => 'Máy chủ không khả dụng, vui lòng thử lại sau.';
  @override
  String get fileUnavailable => 'Tệp không còn khả dụng.';
  @override
  String get unknownAttachment => 'Tệp đính kèm không tồn tại hoặc đã được gửi.';
}

// Path: base.status
class _Translations$base$status$vi extends Translations$base$status$en {
  _Translations$base$status$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get pending => 'Chờ xử lý';
  @override
  String get syncing => 'Đang đồng bộ';
  @override
  String get ready => 'Sẵn sàng';
  @override
  String get failed => 'Thất bại';
  @override
  String get waiting => 'Đang chờ';
  @override
  String get converting => 'Đang chuyển đổi';
  @override
  String get notAvailable => 'Không khả dụng';
  @override
  String get converted => 'Đã chuyển đổi';
}

// Path: base.user
class _Translations$base$user$vi extends Translations$base$user$en {
  _Translations$base$user$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get userName => 'Tên người dùng';
  @override
  String get email => 'Email';
  @override
  String get emailOptional => 'Email (không bắt buộc)';
  @override
  String get userNameOrEmail => 'Tên người dùng hoặc email';
  @override
  String get password => 'Mật khẩu';
  @override
  String passwordHint({required Object min, required Object max}) => 'Từ ${min} đến ${max} ký tự';
  @override
  String get currentPassword => 'Mật khẩu hiện tại';
  @override
  String get newPassword => 'Mật khẩu mới';
  @override
  String get confirmPassword => 'Xác nhận mật khẩu mới';
  @override
  String get missingPassword => 'Thiếu mật khẩu';
  @override
  String passwordLengthInvalid({required Object min, required Object max}) => 'Mật khẩu phải có từ ${min} đến ${max} ký tự';
  @override
  String newPasswordLengthInvalid({required Object min, required Object max}) => 'Mật khẩu mới phải có từ ${min} đến ${max} ký tự.';
  @override
  String get passwordMismatch => 'Mật khẩu mới không khớp.';
  @override
  String get wrongPassword => 'Mật khẩu hiện tại không đúng';
  @override
  String get samePassword => 'Mật khẩu mới phải khác mật khẩu hiện tại';
  @override
  String get role => 'Vai trò';
  @override
  String get roleAdmin => 'Quản trị viên';
  @override
  String get roleUser => 'Người dùng';
  @override
  String get missingUserName => 'Thiếu tên người dùng';
  @override
  String get missingUserNameOrEmail => 'Thiếu tên người dùng hoặc email';
  @override
  String userNameInvalid({required Object max}) => 'Tên người dùng phải gồm 1 đến ${max} ký tự là chữ cái, chữ số, \'.\', \'_\' hoặc \'-\'';
  @override
  String get emailInvalid => 'Email không hợp lệ';
  @override
  String get userNameTaken => 'Tên người dùng này đã được sử dụng';
  @override
  String get emailTaken => 'Email này đã được sử dụng';
}

// Path: base.app
class _Translations$base$app$vi extends Translations$base$app$en {
  _Translations$base$app$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get logoAlt => 'Logo Repolupe';
  @override
  late final _Translations$base$app$navigation$vi navigation = _Translations$base$app$navigation$vi._(_root);
  @override
  late final _Translations$base$app$mainContainer$vi mainContainer = _Translations$base$app$mainContainer$vi._(_root);
  @override
  late final _Translations$base$app$genericDeleteDialog$vi genericDeleteDialog = _Translations$base$app$genericDeleteDialog$vi._(_root);
}

// Path: base.login
class _Translations$base$login$vi extends Translations$base$login$en {
  _Translations$base$login$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get login => 'Đăng nhập';
  @override
  String get wrongCredentials => 'Sai tên người dùng hoặc mật khẩu';
  @override
  late final _Translations$base$login$changePasswordPage$vi changePasswordPage = _Translations$base$login$changePasswordPage$vi._(_root);
  @override
  String loginFailed({required Object error}) => 'Đăng nhập thất bại: ${error}';
}

// Path: base.chat
class _Translations$base$chat$vi extends Translations$base$chat$en {
  _Translations$base$chat$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Đoạn chat';
  @override
  String get noChats => 'Chưa có đoạn chat nào';
  @override
  String get placeholder => 'Tin nhắn';
  @override
  String get unknownModel => 'Mô hình đã chọn không còn khả dụng.';
  @override
  String get unknownAttachment => 'Tệp đã đính kèm không còn khả dụng, vui lòng đính kèm lại.';
  @override
  String get noModelConfigured => 'Chưa có mô hình ngôn ngữ nào được cấu hình. Hãy nhờ quản trị viên thêm nhà cung cấp LLM.';
  @override
  String get rateLimited => 'Hiện có quá nhiều câu trả lời đang được tạo. Vui lòng chờ đến khi một câu trả lời hoàn tất.';
  @override
  String get allRepositories => 'Tất cả kho lưu trữ';
  @override
  String repositoryCount({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    zero: 'Không có kho lưu trữ nào',
    one: '1 kho lưu trữ',
    other: '${count} kho lưu trữ',
  );
  @override
  String get allMcpServers => 'Tất cả máy chủ MCP';
  @override
  String mcpServerCount({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    zero: 'Không có máy chủ MCP nào',
    one: '1 máy chủ MCP',
    other: '${count} máy chủ MCP',
  );
  @override
  String moveCount({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    one: '1 lần di chuyển',
    other: '${count} lần di chuyển',
  );
  @override
  String get temporary => 'Đoạn chat tạm thời';
  @override
  late final _Translations$base$chat$startPage$vi startPage = _Translations$base$chat$startPage$vi._(_root);
  @override
  late final _Translations$base$chat$page$vi page = _Translations$base$chat$page$vi._(_root);
  @override
  late final _Translations$base$chat$messageInput$vi messageInput = _Translations$base$chat$messageInput$vi._(_root);
  @override
  late final _Translations$base$chat$assistantMessage$vi assistantMessage = _Translations$base$chat$assistantMessage$vi._(_root);
  @override
  late final _Translations$base$chat$userMessage$vi userMessage = _Translations$base$chat$userMessage$vi._(_root);
  @override
  late final _Translations$base$chat$toolCallList$vi toolCallList = _Translations$base$chat$toolCallList$vi._(_root);
  @override
  late final _Translations$base$chat$toolCallLabel$vi toolCallLabel = _Translations$base$chat$toolCallLabel$vi._(_root);
  @override
  late final _Translations$base$chat$toolCallDialog$vi toolCallDialog = _Translations$base$chat$toolCallDialog$vi._(_root);
  @override
  late final _Translations$base$chat$rawAnswerDialog$vi rawAnswerDialog = _Translations$base$chat$rawAnswerDialog$vi._(_root);
  @override
  late final _Translations$base$chat$proposedCommitPanel$vi proposedCommitPanel = _Translations$base$chat$proposedCommitPanel$vi._(_root);
  @override
  late final _Translations$base$chat$renameDialog$vi renameDialog = _Translations$base$chat$renameDialog$vi._(_root);
  @override
  late final _Translations$base$chat$usageDialog$vi usageDialog = _Translations$base$chat$usageDialog$vi._(_root);
  @override
  late final _Translations$base$chat$durationDialog$vi durationDialog = _Translations$base$chat$durationDialog$vi._(_root);
  @override
  late final _Translations$base$chat$olderPage$vi olderPage = _Translations$base$chat$olderPage$vi._(_root);
  @override
  String loadFailed({required Object error}) => 'Không thể tải danh sách đoạn chat: ${error}';
}

// Path: base.settings
class _Translations$base$settings$vi extends Translations$base$settings$en {
  _Translations$base$settings$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Cài đặt';
  @override
  late final _Translations$base$settings$themeMode$vi themeMode = _Translations$base$settings$themeMode$vi._(_root);
  @override
  late final _Translations$base$settings$page$vi page = _Translations$base$settings$page$vi._(_root);
  @override
  late final _Translations$base$settings$account$vi account = _Translations$base$settings$account$vi._(_root);
  @override
  late final _Translations$base$settings$profile$vi profile = _Translations$base$settings$profile$vi._(_root);
  @override
  late final _Translations$base$settings$preferences$vi preferences = _Translations$base$settings$preferences$vi._(_root);
}

// Path: base.repositories
class _Translations$base$repositories$vi extends Translations$base$repositories$en {
  _Translations$base$repositories$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Kho lưu trữ';
  @override
  String get newRepository => 'Kho lưu trữ mới';
  @override
  String get size => 'Dung lượng';
  @override
  String get share => 'Chia sẻ';
  @override
  String get remote => 'Từ xa';
  @override
  String get local => 'Cục bộ';
  @override
  String get remoteUrl => 'URL từ xa';
  @override
  String get branch => 'Nhánh';
  @override
  String get description => 'Mô tả';
  @override
  String get accessToken => 'Token truy cập';
  @override
  String get syncInterval => 'Khoảng thời gian đồng bộ';
  @override
  String get allowCommits => 'Bật quyền ghi';
  @override
  String descriptionTooLong({required Object max}) => 'Mô tả tối đa ${max} ký tự';
  @override
  String get missingRemoteUrl => 'Thiếu URL từ xa';
  @override
  String get missingBranch => 'Thiếu nhánh';
  @override
  late final _Translations$base$repositories$pollInterval$vi pollInterval = _Translations$base$repositories$pollInterval$vi._(_root);
  @override
  late final _Translations$base$repositories$listPage$vi listPage = _Translations$base$repositories$listPage$vi._(_root);
  @override
  late final _Translations$base$repositories$page$vi page = _Translations$base$repositories$page$vi._(_root);
  @override
  late final _Translations$base$repositories$kindDialog$vi kindDialog = _Translations$base$repositories$kindDialog$vi._(_root);
  @override
  late final _Translations$base$repositories$createDialog$vi createDialog = _Translations$base$repositories$createDialog$vi._(_root);
  @override
  late final _Translations$base$repositories$editDialog$vi editDialog = _Translations$base$repositories$editDialog$vi._(_root);
  @override
  late final _Translations$base$repositories$usersCard$vi usersCard = _Translations$base$repositories$usersCard$vi._(_root);
  @override
  late final _Translations$base$repositories$shareDialog$vi shareDialog = _Translations$base$repositories$shareDialog$vi._(_root);
}

// Path: base.documents
class _Translations$base$documents$vi extends Translations$base$documents$en {
  _Translations$base$documents$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Tài liệu';
  @override
  String get description => 'Tài liệu được chuyển đổi thành văn bản ở chế độ nền để mô hình có thể đọc chúng.';
  @override
  String get document => 'Tài liệu';
  @override
  String get detailsColumn => 'Chi tiết';
  @override
  String get noData => 'Không có tài liệu nào trong danh mục này.';
  @override
  late final _Translations$base$documents$card$vi card = _Translations$base$documents$card$vi._(_root);
  @override
  late final _Translations$base$documents$statusFilter$vi statusFilter = _Translations$base$documents$statusFilter$vi._(_root);
  @override
  late final _Translations$base$documents$details$vi details = _Translations$base$documents$details$vi._(_root);
  @override
  String loadFailed({required Object error}) => 'Không thể tải danh sách tài liệu: ${error}';
}

// Path: base.mcpServers
class _Translations$base$mcpServers$vi extends Translations$base$mcpServers$en {
  _Translations$base$mcpServers$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Máy chủ MCP';
  @override
  String get newServer => 'Máy chủ mới';
  @override
  String unreachable({required Object error}) =>
      '${error}. Hãy kiểm tra URL: URL phải trỏ đến endpoint MCP của máy chủ (Streamable HTTP), thường kết thúc bằng /mcp.';
  @override
  late final _Translations$base$mcpServers$status$vi status = _Translations$base$mcpServers$status$vi._(_root);
  @override
  late final _Translations$base$mcpServers$kind$vi kind = _Translations$base$mcpServers$kind$vi._(_root);
  @override
  late final _Translations$base$mcpServers$page$vi page = _Translations$base$mcpServers$page$vi._(_root);
  @override
  late final _Translations$base$mcpServers$dialog$vi dialog = _Translations$base$mcpServers$dialog$vi._(_root);
  @override
  late final _Translations$base$mcpServers$sharing$vi sharing = _Translations$base$mcpServers$sharing$vi._(_root);
  @override
  late final _Translations$base$mcpServers$shareDialog$vi shareDialog = _Translations$base$mcpServers$shareDialog$vi._(_root);
  @override
  late final _Translations$base$mcpServers$callback$vi callback = _Translations$base$mcpServers$callback$vi._(_root);
}

// Path: base.admin
class _Translations$base$admin$vi extends Translations$base$admin$en {
  _Translations$base$admin$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$base$admin$users$vi users = _Translations$base$admin$users$vi._(_root);
  @override
  late final _Translations$base$admin$llm$vi llm = _Translations$base$admin$llm$vi._(_root);
  @override
  late final _Translations$base$admin$config$vi config = _Translations$base$admin$config$vi._(_root);
  @override
  late final _Translations$base$admin$extraction$vi extraction = _Translations$base$admin$extraction$vi._(_root);
  @override
  late final _Translations$base$admin$server$vi server = _Translations$base$admin$server$vi._(_root);
}

// Path: flutter.common
class _Translations$flutter$common$vi extends Translations$flutter$common$en {
  _Translations$flutter$common$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$common$unsavedChanges$vi unsavedChanges = _Translations$flutter$common$unsavedChanges$vi._(_root);
}

// Path: flutter.setup
class _Translations$flutter$setup$vi extends Translations$flutter$setup$en {
  _Translations$flutter$setup$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get addAccount => 'Thêm tài khoản';
  @override
  String get intro => 'Đăng nhập vào máy chủ Repolupe của bạn, hoặc chạy Repolupe trên thiết bị này.';
  @override
  String get introRemote => 'Đăng nhập vào máy chủ Repolupe của bạn.';
  @override
  String get server => 'Máy chủ';
  @override
  String get remoteDescription => 'Đăng nhập vào một máy chủ Repolupe và dùng các kho lưu trữ và mô hình của máy chủ đó.';
  @override
  String get localDescription => 'Chạy Repolupe trong ứng dụng. Đoạn chat và kho lưu trữ chỉ được lưu trên thiết bị này.';
}

// Path: flutter.account
class _Translations$flutter$account$vi extends Translations$flutter$account$en {
  _Translations$flutter$account$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get thisDevice => 'Thiết bị này';
  @override
  String get invalidApiUrl => 'Địa chỉ máy chủ không hợp lệ.';
  @override
  String localStartFailed({required Object message}) => 'Không thể khởi chạy Repolupe trên thiết bị này: ${message}';
  @override
  String sessionExpired({required Object server}) => 'Phiên đăng nhập của bạn trên ${server} đã kết thúc. Vui lòng đăng nhập lại.';
}

// Path: flutter.chat
class _Translations$flutter$chat$vi extends Translations$flutter$chat$en {
  _Translations$flutter$chat$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$chat$page$vi page = _Translations$flutter$chat$page$vi._(_root);
  @override
  late final _Translations$flutter$chat$leaveTemporaryDialog$vi leaveTemporaryDialog = _Translations$flutter$chat$leaveTemporaryDialog$vi._(_root);
  @override
  late final _Translations$flutter$chat$assistantMessage$vi assistantMessage = _Translations$flutter$chat$assistantMessage$vi._(_root);
  @override
  late final _Translations$flutter$chat$markdownContent$vi markdownContent = _Translations$flutter$chat$markdownContent$vi._(_root);
  @override
  late final _Translations$flutter$chat$toolCallPage$vi toolCallPage = _Translations$flutter$chat$toolCallPage$vi._(_root);
  @override
  late final _Translations$flutter$chat$fileContent$vi fileContent = _Translations$flutter$chat$fileContent$vi._(_root);
  @override
  late final _Translations$flutter$chat$proposedCommitPage$vi proposedCommitPage = _Translations$flutter$chat$proposedCommitPage$vi._(_root);
}

// Path: flutter.settings
class _Translations$flutter$settings$vi extends Translations$flutter$settings$en {
  _Translations$flutter$settings$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$settings$page$vi page = _Translations$flutter$settings$page$vi._(_root);
  @override
  late final _Translations$flutter$settings$changePasswordPage$vi changePasswordPage = _Translations$flutter$settings$changePasswordPage$vi._(_root);
  @override
  late final _Translations$flutter$settings$accountSheet$vi accountSheet = _Translations$flutter$settings$accountSheet$vi._(_root);
  @override
  late final _Translations$flutter$settings$preferences$vi preferences = _Translations$flutter$settings$preferences$vi._(_root);
}

// Path: flutter.validation
class _Translations$flutter$validation$vi extends Translations$flutter$validation$en {
  _Translations$flutter$validation$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get invalidCurrency => 'Tiền tệ không hợp lệ, cần một mã như USD hoặc EUR';
}

// Path: flutter.repositories
class _Translations$flutter$repositories$vi extends Translations$flutter$repositories$en {
  _Translations$flutter$repositories$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get statusUnknown => 'Không xác định';
  @override
  late final _Translations$flutter$repositories$listPage$vi listPage = _Translations$flutter$repositories$listPage$vi._(_root);
  @override
  late final _Translations$flutter$repositories$page$vi page = _Translations$flutter$repositories$page$vi._(_root);
  @override
  late final _Translations$flutter$repositories$form$vi form = _Translations$flutter$repositories$form$vi._(_root);
  @override
  late final _Translations$flutter$repositories$usersCard$vi usersCard = _Translations$flutter$repositories$usersCard$vi._(_root);
}

// Path: flutter.mcpServers
class _Translations$flutter$mcpServers$vi extends Translations$flutter$mcpServers$en {
  _Translations$flutter$mcpServers$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$mcpServers$page$vi page = _Translations$flutter$mcpServers$page$vi._(_root);
  @override
  late final _Translations$flutter$mcpServers$form$vi form = _Translations$flutter$mcpServers$form$vi._(_root);
  @override
  late final _Translations$flutter$mcpServers$namePicker$vi namePicker = _Translations$flutter$mcpServers$namePicker$vi._(_root);
}

// Path: flutter.documents
class _Translations$flutter$documents$vi extends Translations$flutter$documents$en {
  _Translations$flutter$documents$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get notSynced => 'Chưa đồng bộ';
  @override
  String get noDocuments => 'Không có tài liệu nào';
  @override
  String showMore({required Object remaining}) => 'Xem thêm (còn ${remaining})';
  @override
  late final _Translations$flutter$documents$details$vi details = _Translations$flutter$documents$details$vi._(_root);
}

// Path: flutter.format
class _Translations$flutter$format$vi extends Translations$flutter$format$en {
  _Translations$flutter$format$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$format$day$vi day = _Translations$flutter$format$day$vi._(_root);
  @override
  late final _Translations$flutter$format$relative$vi relative = _Translations$flutter$format$relative$vi._(_root);
}

// Path: flutter.admin
class _Translations$flutter$admin$vi extends Translations$flutter$admin$en {
  _Translations$flutter$admin$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$admin$users$vi users = _Translations$flutter$admin$users$vi._(_root);
  @override
  late final _Translations$flutter$admin$llm$vi llm = _Translations$flutter$admin$llm$vi._(_root);
  @override
  late final _Translations$flutter$admin$config$vi config = _Translations$flutter$admin$config$vi._(_root);
  @override
  late final _Translations$flutter$admin$extraction$vi extraction = _Translations$flutter$admin$extraction$vi._(_root);
}

// Path: base.app.navigation
class _Translations$base$app$navigation$vi extends Translations$base$app$navigation$en {
  _Translations$base$app$navigation$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get expand => 'Mở rộng';
  @override
  String get expandNavigation => 'Mở rộng thanh điều hướng';
  @override
  String get collapse => 'Thu gọn';
  @override
  String get collapseNavigation => 'Thu gọn thanh điều hướng';
  @override
  String get newChat => 'Đoạn chat mới';
  @override
  String get older => 'Cũ hơn';
}

// Path: base.app.mainContainer
class _Translations$base$app$mainContainer$vi extends Translations$base$app$mainContainer$en {
  _Translations$base$app$mainContainer$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String quotedTitle({required Object title}) => '"${title}"';
}

// Path: base.app.genericDeleteDialog
class _Translations$base$app$genericDeleteDialog$vi extends Translations$base$app$genericDeleteDialog$en {
  _Translations$base$app$genericDeleteDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String verifyPrompt({required Object verify}) => 'Vui lòng xác nhận bằng cách nhập "${verify}" vào ô bên dưới:';
  @override
  String get verification => 'Xác nhận';
  @override
  String get mismatch => 'Không khớp.';
}

// Path: base.login.changePasswordPage
class _Translations$base$login$changePasswordPage$vi extends Translations$base$login$changePasswordPage$en {
  _Translations$base$login$changePasswordPage$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Đổi mật khẩu';
  @override
  String get submit => 'Đổi mật khẩu';
  @override
  String get logout => 'Đăng xuất';
}

// Path: base.chat.startPage
class _Translations$base$chat$startPage$vi extends Translations$base$chat$startPage$en {
  _Translations$base$chat$startPage$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get greeting => 'Bạn muốn biết điều gì?';
  @override
  String greetingName({required Object name}) => 'Xin chào ${name}!';
  @override
  String get loadFailed => 'Không thể tải danh sách kho lưu trữ.';
  @override
  String get noModel => 'Chưa có mô hình ngôn ngữ nào được cấu hình nên chưa thể trả lời câu hỏi.';
  @override
  String addProvider({required Object link}) => '${link} để bắt đầu.';
  @override
  String get addProviderLink => 'Thêm nhà cung cấp LLM';
  @override
  String get askAdmin => 'Hãy nhờ quản trị viên cấu hình nhà cung cấp LLM.';
  @override
  String get waitForUpload => 'Vui lòng chờ tệp được tải lên xong.';
  @override
  String get enterQuestion => 'Vui lòng nhập câu hỏi.';
  @override
  String get unknownRepository => 'Một kho lưu trữ đã chọn không còn khả dụng.';
  @override
  String get unknownMcpServer => 'Một máy chủ MCP đã chọn không còn khả dụng.';
}

// Path: base.chat.page
class _Translations$base$chat$page$vi extends Translations$base$chat$page$en {
  _Translations$base$chat$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get actions => 'Thao tác với đoạn chat';
  @override
  String get rename => 'Đổi tên';
  @override
  String get deleteTitle => 'Xóa đoạn chat';
  @override
  String deleteConfirm({required Object title}) => 'Bạn có chắc muốn xóa "${title}" cùng tất cả tin nhắn trong đó?';
  @override
  String get connectionLost => 'Mất kết nối với câu trả lời. Hãy tải lại trang để thử lại.';
  @override
  String get notFound => 'Không tìm thấy đoạn chat';
  @override
  String get renamed => 'Đã đổi tên đoạn chat.';
  @override
  String get deleted => 'Đã xóa đoạn chat.';
  @override
  String openFailed({required Object error}) => 'Không thể mở đoạn chat: ${error}';
  @override
  String sendFailed({required Object error}) => 'Không thể gửi tin nhắn: ${error}';
  @override
  String retryFailed({required Object error}) => 'Không thể tạo lại câu trả lời: ${error}';
  @override
  String stopFailed({required Object error}) => 'Không thể dừng câu trả lời: ${error}';
  @override
  String renameFailed({required Object error}) => 'Không thể đổi tên đoạn chat: ${error}';
  @override
  String changeModelFailed({required Object error}) => 'Không thể đổi mô hình: ${error}';
  @override
  String deleteFailed({required Object error}) => 'Không thể xóa đoạn chat: ${error}';
}

// Path: base.chat.messageInput
class _Translations$base$chat$messageInput$vi extends Translations$base$chat$messageInput$en {
  _Translations$base$chat$messageInput$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get stop => 'Dừng';
  @override
  String get send => 'Gửi';
  @override
  String get attach => 'Đính kèm tệp';
  @override
  String get options => 'Tùy chọn';
  @override
  String get dropHint => 'Thả tệp vào đây để đính kèm';
  @override
  String fileTooLarge({required Object max}) => 'Tệp quá lớn, dung lượng tối đa là ${max}.';
  @override
  String uploadFailed({required Object error}) => 'Không thể tải tệp lên: ${error}';
  @override
  String get oneFileOnly => 'Mỗi tin nhắn chỉ có thể đính kèm một tệp.';
}

// Path: base.chat.assistantMessage
class _Translations$base$chat$assistantMessage$vi extends Translations$base$chat$assistantMessage$en {
  _Translations$base$chat$assistantMessage$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get thinking => 'Đang suy nghĩ…';
  @override
  String get noAnswer => '(Không có câu trả lời)';
  @override
  String proposedStore({required Object path}) => 'Đề xuất lưu thành ${path}';
  @override
  String proposedChange({required Object path}) => 'Đề xuất thay đổi ${path}';
  @override
  String proposedMoves({required Object moves}) => 'Đề xuất di chuyển: ${moves}';
  @override
  String get failed => 'Không thể tạo câu trả lời.';
  @override
  String get cancelled => 'Đã hủy';
  @override
  String get showUsage => 'Xem lượng token sử dụng';
  @override
  String get showDuration => 'Xem thời gian';
  @override
  String get showToolCalls => 'Xem các lệnh gọi công cụ';
  @override
  String toolCount({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    one: '${count} công cụ',
    other: '${count} công cụ',
  );
  @override
  String durationSeconds({required Object seconds}) => '${seconds} giây';
  @override
  String durationMinutes({required Object minutes, required Object seconds}) => '${minutes} phút ${seconds} giây';
}

// Path: base.chat.userMessage
class _Translations$base$chat$userMessage$vi extends Translations$base$chat$userMessage$en {
  _Translations$base$chat$userMessage$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String download({required Object name}) => 'Tải xuống ${name}';
}

// Path: base.chat.toolCallList
class _Translations$base$chat$toolCallList$vi extends Translations$base$chat$toolCallList$en {
  _Translations$base$chat$toolCallList$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get running => 'Đang sử dụng công cụ';
  @override
  String get readingAttachments => 'Đang đọc tệp đính kèm';
  @override
  String get lookingUp => 'Đang tra cứu';
  @override
  String get calculating => 'Đang tính toán';
}

// Path: base.chat.toolCallLabel
class _Translations$base$chat$toolCallLabel$vi extends Translations$base$chat$toolCallLabel$en {
  _Translations$base$chat$toolCallLabel$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String grepPatternIn({required Object pattern, required Object where}) => '"${pattern}" trong ${where}';
  @override
  String grepIn({required Object where}) => 'trong ${where}';
}

// Path: base.chat.toolCallDialog
class _Translations$base$chat$toolCallDialog$vi extends Translations$base$chat$toolCallDialog$en {
  _Translations$base$chat$toolCallDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get stillRunning => 'Vẫn đang chạy.';
  @override
  String get noOutput => 'Không có đầu ra.';
  @override
  String loadFailed({required Object error}) => 'Không thể tải lệnh gọi công cụ: ${error}';
}

// Path: base.chat.rawAnswerDialog
class _Translations$base$chat$rawAnswerDialog$vi extends Translations$base$chat$rawAnswerDialog$en {
  _Translations$base$chat$rawAnswerDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Câu trả lời thô';
  @override
  String get systemPrompt => 'Lời nhắc hệ thống';
  @override
  String get show => 'Xem';
  @override
  String get hide => 'Ẩn';
  @override
  String get tools => 'Công cụ';
  @override
  String get messages => 'Tin nhắn';
  @override
  String get user => 'Người dùng';
  @override
  String get assistant => 'Trợ lý';
  @override
  String get reasoning => 'Suy luận';
  @override
  String get reasoningWithheld => 'Nhà cung cấp đã giữ lại phần suy luận.';
  @override
  String get toolUse => 'Lệnh gọi công cụ';
  @override
  String get toolResult => 'Kết quả công cụ';
  @override
  String get error => 'Lỗi';
  @override
  String get notAvailable => 'Không có dữ liệu nào được lưu cho câu trả lời này. Các câu trả lời bị gián đoạn do khởi động lại không có dữ liệu.';
  @override
  String get copy => 'Sao chép dưới dạng JSON';
  @override
  String get copied => 'Đã sao chép vào bộ nhớ tạm.';
  @override
  String get copyFailed => 'Không thể sao chép vào bộ nhớ tạm.';
  @override
  String loadFailed({required Object error}) => 'Không thể tải câu trả lời thô: ${error}';
}

// Path: base.chat.proposedCommitPanel
class _Translations$base$chat$proposedCommitPanel$vi extends Translations$base$chat$proposedCommitPanel$en {
  _Translations$base$chat$proposedCommitPanel$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get applied => 'Đã áp dụng';
  @override
  String appliedAt({required Object relative, required Object dateTime}) => 'Đã áp dụng ${relative} (${dateTime})';
  @override
  String get more => 'Thêm tùy chọn';
  @override
  String get downloadPatch => 'Tải xuống dưới dạng tệp patch';
  @override
  String get willDelete => 'Tệp này sẽ bị xóa.';
  @override
  String get willCreate => 'Tệp này sẽ được tạo.';
  @override
  String get removed => 'Đã xóa';
  @override
  String get unchangedLines => 'Các dòng không thay đổi';
  @override
  String removedLine({required Object text}) => 'đã xóa: ${text}';
  @override
  String addedLine({required Object text}) => 'đã thêm: ${text}';
  @override
  String movedTo({required Object from, required Object to}) => '${from} được di chuyển đến ${to}';
  @override
  String folderFiles({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    one: 'Thư mục có 1 tệp',
    other: 'Thư mục có ${count} tệp',
  );
  @override
  String get noPreview => 'Không có bản xem trước cho loại tệp này.';
  @override
  String get cannotCommit => 'Chỉ chủ sở hữu kho lưu trữ này và những người dùng được họ cấp quyền ghi mới có thể áp dụng thay đổi.';
  @override
  String get enableAutoCommit => 'Bật tự động áp dụng';
  @override
  String get autoCommitTitle => 'Bật tự động áp dụng?';
  @override
  String get autoCommitText =>
      'Từ giờ, các thay đổi do trợ lý đề xuất sẽ được áp dụng ngay khi câu trả lời hoàn tất mà không cần hỏi bạn. Thay đổi này sẽ được áp dụng ngay bây giờ. Bạn có thể tắt tính năng này trong phần tùy chọn.';
  @override
  String get autoCommitConfirm => 'Bật và áp dụng';
  @override
  String get apply => 'Áp dụng thay đổi';
  @override
  String get tryAgain => 'Thử lại';
  @override
  String appliedTo({required Object name}) => 'Đã áp dụng thay đổi cho ${name}';
  @override
  String get appliedMoves => 'Đã áp dụng các lần di chuyển';
  @override
  String applyFailed({required Object error}) => 'Không thể áp dụng thay đổi: ${error}';
  @override
  String downloadFailed({required Object error}) => 'Không thể tải xuống patch: ${error}';
}

// Path: base.chat.renameDialog
class _Translations$base$chat$renameDialog$vi extends Translations$base$chat$renameDialog$en {
  _Translations$base$chat$renameDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Đổi tên đoạn chat';
  @override
  String get label => 'Tiêu đề';
  @override
  String maxLength({required Object max}) => 'Tối đa ${max} ký tự.';
}

// Path: base.chat.usageDialog
class _Translations$base$chat$usageDialog$vi extends Translations$base$chat$usageDialog$en {
  _Translations$base$chat$usageDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Lượng token sử dụng';
  @override
  String get showRaw => 'Xem những gì mô hình ngôn ngữ đã nhận và trả về';
  @override
  String get raw => 'Thô';
  @override
  String get type => 'Loại';
  @override
  String get tokens => 'Token';
  @override
  String get inputHint => 'Không đọc từ hoặc ghi vào bộ nhớ đệm';
  @override
  String get cacheRead => 'Đọc bộ nhớ đệm';
  @override
  String get cacheReadHint => 'Đầu vào được đọc từ bộ nhớ đệm';
  @override
  String get cacheWrite => 'Ghi bộ nhớ đệm';
  @override
  String get cacheWriteHint => 'Đầu vào được ghi vào bộ nhớ đệm';
  @override
  String get outputHint => 'Bao gồm cả phần suy luận';
  @override
  String get total => 'Tổng';
  @override
  String get cost => 'Chi phí';
  @override
  String pricePerMillion({required Object price}) => '${price} cho 1 triệu token';
}

// Path: base.chat.durationDialog
class _Translations$base$chat$durationDialog$vi extends Translations$base$chat$durationDialog$en {
  _Translations$base$chat$durationDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Thời gian';
  @override
  String get model => 'Mô hình ngôn ngữ';
  @override
  String get speed => 'Tốc độ đầu ra';
  @override
  String tokensPerSecond({required Object speed}) => '${speed} token/giây';
  @override
  String get tools => 'Lệnh gọi công cụ';
  @override
  String callCount({required Object count}) => '${count}×';
  @override
  String lessThan({required Object duration}) => '<${duration}';
  @override
  String get toolsSum => 'Công cụ, cộng dồn';
  @override
  String get toolsReal => 'Công cụ, thời gian thực';
  @override
  String get toolsRealHint => 'Các công cụ chạy song song, nên đây là thời gian bạn thực sự phải chờ chúng';
  @override
  String get total => 'Tổng';
  @override
  String get notMeasured => 'Thời gian của mô hình ngôn ngữ không được đo cho câu trả lời này.';
}

// Path: base.chat.olderPage
class _Translations$base$chat$olderPage$vi extends Translations$base$chat$olderPage$en {
  _Translations$base$chat$olderPage$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Đoạn chat cũ hơn';
  @override
  String get noResults => 'Không tìm thấy đoạn chat nào';
}

// Path: base.settings.themeMode
class _Translations$base$settings$themeMode$vi extends Translations$base$settings$themeMode$en {
  _Translations$base$settings$themeMode$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Giao diện';
  @override
  String get system => 'Hệ thống';
  @override
  String get light => 'Sáng';
  @override
  String get dark => 'Tối';
}

// Path: base.settings.page
class _Translations$base$settings$page$vi extends Translations$base$settings$page$en {
  _Translations$base$settings$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get app => 'Ứng dụng';
  @override
  String get user => 'Người dùng';
  @override
  String get admin => 'Quản trị';
  @override
  String get logout => 'Đăng xuất';
  @override
  String repositoryCount({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    zero: 'Không có kho lưu trữ nào',
    one: '1 kho lưu trữ',
    other: '${count} kho lưu trữ',
  );
  @override
  String mcpServerCount({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    zero: 'Không có máy chủ nào',
    one: '1 máy chủ',
    other: '${count} máy chủ',
  );
  @override
  String get profileEmpty => 'Chưa điền thông tin';
}

// Path: base.settings.account
class _Translations$base$settings$account$vi extends Translations$base$settings$account$en {
  _Translations$base$settings$account$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Tài khoản';
  @override
  late final _Translations$base$settings$account$page$vi page = _Translations$base$settings$account$page$vi._(_root);
  @override
  late final _Translations$base$settings$account$changePasswordDialog$vi changePasswordDialog =
      _Translations$base$settings$account$changePasswordDialog$vi._(_root);
  @override
  late final _Translations$base$settings$account$userNameDialog$vi userNameDialog = _Translations$base$settings$account$userNameDialog$vi._(_root);
  @override
  late final _Translations$base$settings$account$emailDialog$vi emailDialog = _Translations$base$settings$account$emailDialog$vi._(_root);
  @override
  String get loginHint => 'Bạn đăng nhập bằng tên người dùng hoặc email.';
}

// Path: base.settings.profile
class _Translations$base$settings$profile$vi extends Translations$base$settings$profile$en {
  _Translations$base$settings$profile$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Hồ sơ';
  @override
  String get fullName => 'Họ và tên';
  @override
  String get firstName => 'Tên';
  @override
  String get about => 'Giới thiệu';
  @override
  late final _Translations$base$settings$profile$page$vi page = _Translations$base$settings$profile$page$vi._(_root);
  @override
  late final _Translations$base$settings$profile$fullNameDialog$vi fullNameDialog = _Translations$base$settings$profile$fullNameDialog$vi._(_root);
  @override
  late final _Translations$base$settings$profile$firstNameDialog$vi firstNameDialog = _Translations$base$settings$profile$firstNameDialog$vi._(_root);
  @override
  late final _Translations$base$settings$profile$aboutDialog$vi aboutDialog = _Translations$base$settings$profile$aboutDialog$vi._(_root);
}

// Path: base.settings.preferences
class _Translations$base$settings$preferences$vi extends Translations$base$settings$preferences$en {
  _Translations$base$settings$preferences$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Tùy chọn';
  @override
  String get language => 'Ngôn ngữ';
  @override
  String browserDefault({required Object locale}) => 'Mặc định của trình duyệt (${locale})';
  @override
  String defaultModel({required Object name}) => 'Mặc định (${name})';
  @override
  String get defaultNone => 'Mặc định (chưa cấu hình)';
  @override
  late final _Translations$base$settings$preferences$page$vi page = _Translations$base$settings$preferences$page$vi._(_root);
  @override
  late final _Translations$base$settings$preferences$localeDialog$vi localeDialog = _Translations$base$settings$preferences$localeDialog$vi._(_root);
  @override
  late final _Translations$base$settings$preferences$modelDialog$vi modelDialog = _Translations$base$settings$preferences$modelDialog$vi._(_root);
}

// Path: base.repositories.pollInterval
class _Translations$base$repositories$pollInterval$vi extends Translations$base$repositories$pollInterval$en {
  _Translations$base$repositories$pollInterval$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get minute => 'Mỗi phút';
  @override
  String get minutes5 => 'Mỗi 5 phút';
  @override
  String get minutes15 => 'Mỗi 15 phút';
  @override
  String get hour => 'Mỗi giờ';
  @override
  String get hours6 => 'Mỗi 6 giờ';
  @override
  String get daily => 'Hằng ngày';
  @override
  String seconds({required Object seconds}) => 'Mỗi ${seconds} giây';
}

// Path: base.repositories.listPage
class _Translations$base$repositories$listPage$vi extends Translations$base$repositories$listPage$en {
  _Translations$base$repositories$listPage$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String count({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    zero: '${count} kho lưu trữ',
    one: '${count} kho lưu trữ',
    other: '${count} kho lưu trữ',
  );
  @override
  String get description =>
      'Các kho lưu trữ của bạn và những kho lưu trữ được chia sẻ với bạn. Trong các đoạn chat, mô hình đọc tệp của chúng để trả lời câu hỏi của bạn.';
  @override
  String get emptyTitle => 'Chưa có kho lưu trữ nào';
  @override
  String get emptyText =>
      'Kho lưu trữ là một nhánh git mà Repolupe sao chép và giữ đồng bộ. Sau khi đồng bộ xong, bạn có thể đặt câu hỏi về nó trong các đoạn chat, và mô hình sẽ đọc các tệp của nó để trả lời.';
  @override
  String get noMatch => 'Không có kho lưu trữ nào khớp với tìm kiếm của bạn.';
  @override
  String get added => 'Đã thêm kho lưu trữ, đang đồng bộ…';
  @override
  String loadFailed({required Object error}) => 'Không thể tải danh sách kho lưu trữ: ${error}';
  @override
  String createFailed({required Object error}) => 'Không thể thêm kho lưu trữ: ${error}';
}

// Path: base.repositories.page
class _Translations$base$repositories$page$vi extends Translations$base$repositories$page$en {
  _Translations$base$repositories$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get ownerIntro => 'Tại đây bạn có thể cập nhật thông tin kho lưu trữ, khởi chạy đồng bộ và chia sẻ kho lưu trữ với người dùng khác.';
  @override
  String get ownerIntroLocal => 'Tại đây bạn có thể cập nhật thông tin kho lưu trữ và chia sẻ kho lưu trữ với người dùng khác.';
  @override
  String get sharedIntro => 'Kho lưu trữ này được chia sẻ với bạn. Tại đây bạn có thể xem thông tin và trạng thái đồng bộ của nó.';
  @override
  String get owner => 'Chủ sở hữu';
  @override
  String get ownerYou => 'Bạn';
  @override
  String get ownerShared => 'Được chia sẻ với bạn';
  @override
  String sizeSplit({required Object git, required Object lfs}) => 'Git ${git}, LFS ${lfs}';
  @override
  String sizeTitle({required Object branch}) => 'Chỉ nhánh ${branch} được tải xuống, nên kho lưu trữ trên máy chủ từ xa có thể lớn hơn';
  @override
  String get created => 'Ngày tạo';
  @override
  String get askQuestion => 'Đặt câu hỏi';
  @override
  String get lastSyncFailed => 'Lần đồng bộ gần nhất thất bại';
  @override
  String get remoteNone => 'Không có (kho lưu trữ cục bộ trên máy chủ này)';
  @override
  String get tokenNone => 'Không có (công khai)';
  @override
  String get tokenSet => 'Đã đặt';
  @override
  String get writeAccess => 'Quyền ghi';
  @override
  String get writeAccessEnabled => 'Đã bật (mô hình có thể đề xuất thay đổi)';
  @override
  String get writeAccessDisabled => 'Đã tắt (mô hình chỉ có thể đọc tệp)';
  @override
  String get leave => 'Rời khỏi';
  @override
  String get sync => 'Đồng bộ';
  @override
  String get interval => 'Khoảng thời gian';
  @override
  String get intervalLocal => 'Sau mỗi commit';
  @override
  String get headCommit => 'Phiên bản hiện tại';
  @override
  String get lastSynced => 'Đồng bộ lần cuối';
  @override
  String get syncStarted => 'Bắt đầu đồng bộ';
  @override
  String get nextSync => 'Lần đồng bộ tiếp theo';
  @override
  String get syncNow => 'Đồng bộ ngay';
  @override
  String get deleteTitle => 'Xóa kho lưu trữ';
  @override
  String get deleteText =>
      'Chỉ bản sao của kho lưu trữ trên máy chủ này bị xóa. Kho lưu trữ từ xa không bị ảnh hưởng. Các đoạn chat và những người dùng được chia sẻ sẽ mất quyền truy cập vào kho lưu trữ này.';
  @override
  String get deleteTextLocal =>
      'Kho lưu trữ này chỉ tồn tại trên máy chủ này, nên các tệp và lịch sử của nó sẽ bị xóa vĩnh viễn. Các đoạn chat và những người dùng được chia sẻ sẽ mất quyền truy cập vào kho lưu trữ này.';
  @override
  String get leaveTitle => 'Rời khỏi kho lưu trữ';
  @override
  String get leaveText =>
      'Bạn sẽ mất quyền truy cập vào kho lưu trữ này, và nó sẽ bị gỡ khỏi các đoạn chat của bạn. Chủ sở hữu có thể chia sẻ lại với bạn.';
  @override
  String get notFound => 'Không tìm thấy kho lưu trữ';
  @override
  String get syncRequested => 'Đã yêu cầu đồng bộ.';
  @override
  String get updated => 'Đã cập nhật kho lưu trữ.';
  @override
  String get deleted => 'Đã xóa kho lưu trữ.';
  @override
  String get left => 'Bạn đã rời khỏi kho lưu trữ.';
  @override
  String loadFailed({required Object error}) => 'Không thể tải kho lưu trữ: ${error}';
  @override
  String syncFailed({required Object error}) => 'Không thể yêu cầu đồng bộ: ${error}';
  @override
  String saveFailed({required Object error}) => 'Không thể lưu kho lưu trữ: ${error}';
  @override
  String deleteFailed({required Object error}) => 'Không thể xóa kho lưu trữ: ${error}';
  @override
  String leaveFailed({required Object error}) => 'Không thể rời khỏi kho lưu trữ: ${error}';
}

// Path: base.repositories.kindDialog
class _Translations$base$repositories$kindDialog$vi extends Translations$base$repositories$kindDialog$en {
  _Translations$base$repositories$kindDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get remoteDescription => 'Sao chép một nhánh của kho lưu trữ git, ví dụ trên GitHub, GitLab hoặc Forgejo, và giữ nó đồng bộ.';
  @override
  String get localDescription => 'Tạo một kho lưu trữ trống chỉ tồn tại trên máy chủ này.';
}

// Path: base.repositories.createDialog
class _Translations$base$repositories$createDialog$vi extends Translations$base$repositories$createDialog$en {
  _Translations$base$repositories$createDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get titleRemote => 'Kho lưu trữ từ xa mới';
  @override
  String get titleLocal => 'Kho lưu trữ cục bộ mới';
  @override
  String get descriptionOptional => 'Mô tả (không bắt buộc)';
  @override
  String get descriptionHint => 'Giúp mô hình quyết định khi nào cần xem kho lưu trữ này.';
  @override
  String get tokenOptional => 'Token truy cập (không bắt buộc)';
  @override
  String get tokenHint => 'Cần thiết cho kho lưu trữ riêng tư.';
  @override
  String get allowCommitsHintLocal => 'Nếu không có quyền ghi, mô hình không thể thêm tệp, nên kho lưu trữ sẽ luôn trống.';
  @override
  String get remoteUrlHintAdmin => 'Với tư cách quản trị viên, bạn cũng có thể dùng http:// và host nội bộ.';
  @override
  String get remoteUrlHintUser => 'Phải dùng https:// và một host phân giải thành địa chỉ công khai.';
  @override
  String get checkingRemote => 'Đang kiểm tra máy chủ từ xa, việc này có thể mất vài giây…';
}

// Path: base.repositories.editDialog
class _Translations$base$repositories$editDialog$vi extends Translations$base$repositories$editDialog$en {
  _Translations$base$repositories$editDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chỉnh sửa kho lưu trữ';
  @override
  String get keepToken => 'Giữ token hiện tại';
  @override
  String keepTokenWithHint({required Object hint}) => 'Giữ token hiện tại (•••• ${hint})';
  @override
  String get removeToken => 'Xóa token (kho lưu trữ công khai)';
  @override
  String get noToken => 'Không có token (kho lưu trữ công khai)';
  @override
  String get setToken => 'Đặt token mới';
  @override
  String get newToken => 'Token truy cập mới';
  @override
  String get newTokenHint => 'Một token có quyền đọc, ví dụ personal access token.';
  @override
  String get hostChanged =>
      'Kho lưu trữ từ xa đã chuyển sang host khác, nên không thể giữ token hiện tại. Hãy đặt token mới, hoặc xóa token nếu kho lưu trữ từ xa mới là công khai.';
  @override
  String get missingToken => 'Thiếu token';
}

// Path: base.repositories.usersCard
class _Translations$base$repositories$usersCard$vi extends Translations$base$repositories$usersCard$en {
  _Translations$base$repositories$usersCard$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chia sẻ';
  @override
  String get description =>
      'Người dùng được chia sẻ có thể đọc kho lưu trữ này và dùng nó trong các đoạn chat của họ, nhưng không thể thay đổi, đồng bộ hoặc xóa nó. Nếu quyền ghi được bật, bạn có thể cho phép họ áp dụng các thay đổi mà mô hình đề xuất, bằng token truy cập của kho lưu trữ này.';
  @override
  String get descriptionLocal =>
      'Người dùng được chia sẻ có thể đọc kho lưu trữ này và dùng nó trong các đoạn chat của họ, nhưng không thể thay đổi hoặc xóa nó. Nếu quyền ghi được bật, bạn có thể cho phép họ áp dụng các thay đổi mà mô hình đề xuất.';
  @override
  String get notShared => 'Chưa chia sẻ với ai';
  @override
  String get user => 'Người dùng';
  @override
  String get sharedAt => 'Ngày chia sẻ';
  @override
  String get canCommit => 'Quyền ghi';
  @override
  String get canCommitOff => 'Hãy bật quyền ghi cho kho lưu trữ trước';
  @override
  String get stopSharing => 'Ngừng chia sẻ';
  @override
  String get stopSharingTitle => 'Ngừng chia sẻ';
  @override
  String stopSharingText({required Object name}) => '${name} sẽ mất quyền truy cập vào kho lưu trữ này, và nó sẽ bị gỡ khỏi các đoạn chat của họ.';
  @override
  String get shared => 'Đã chia sẻ kho lưu trữ.';
  @override
  String get unknownUser => 'Không có người dùng nào với tên người dùng hoặc email này';
  @override
  String get stopped => 'Đã ngừng chia sẻ.';
  @override
  String loadFailed({required Object error}) => 'Không thể tải danh sách người dùng: ${error}';
  @override
  String shareFailed({required Object error}) => 'Không thể chia sẻ kho lưu trữ: ${error}';
  @override
  String canCommitFailed({required Object error}) => 'Không thể thay đổi quyền ghi: ${error}';
  @override
  String stopFailed({required Object error}) => 'Không thể ngừng chia sẻ: ${error}';
}

// Path: base.repositories.shareDialog
class _Translations$base$repositories$shareDialog$vi extends Translations$base$repositories$shareDialog$en {
  _Translations$base$repositories$shareDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chia sẻ kho lưu trữ';
  @override
  String get description =>
      'Người dùng này có thể đọc kho lưu trữ này và dùng nó trong các đoạn chat của họ, nhưng không thể thay đổi, đồng bộ hoặc xóa nó.';
}

// Path: base.documents.card
class _Translations$base$documents$card$vi extends Translations$base$documents$card$en {
  _Translations$base$documents$card$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String paused({required Object time}) => 'Dịch vụ OCR không khả dụng. Việc chuyển đổi được tạm dừng đến ${time}.';
}

// Path: base.documents.statusFilter
class _Translations$base$documents$statusFilter$vi extends Translations$base$documents$statusFilter$en {
  _Translations$base$documents$statusFilter$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get filterByStatus => 'Lọc theo trạng thái';
  @override
  String get all => 'Tất cả';
}

// Path: base.documents.details
class _Translations$base$documents$details$vi extends Translations$base$documents$details$en {
  _Translations$base$documents$details$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String started({required Object relative}) => 'Bắt đầu ${relative}';
  @override
  String skipped({required Object reason, required Object relative}) => '${reason} Sẽ thử lại ${relative}.';
  @override
  String get lfsObjectMissing => 'Tệp được lưu bằng Git LFS và không thể tải xuống.';
  @override
  String get unreadable => 'Không thể đọc tệp.';
  @override
  String get settingsChanged => 'Cài đặt đã thay đổi';
  @override
  String get kNew => 'Mới';
}

// Path: base.mcpServers.status
class _Translations$base$mcpServers$status$vi extends Translations$base$mcpServers$status$en {
  _Translations$base$mcpServers$status$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get authorizationRequired => 'Cần đăng nhập';
  @override
  String get unknown => 'Không xác định';
}

// Path: base.mcpServers.kind
class _Translations$base$mcpServers$kind$vi extends Translations$base$mcpServers$kind$en {
  _Translations$base$mcpServers$kind$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get search => 'Tìm kiếm';
  @override
  String get webScraping => 'Thu thập dữ liệu web';
  @override
  String get documentation => 'Tài liệu';
  @override
  String get devTools => 'Công cụ phát triển';
  @override
  String get cloud => 'Đám mây';
  @override
  String get database => 'Cơ sở dữ liệu';
  @override
  String get observability => 'Giám sát';
  @override
  String get projectManagement => 'Quản lý dự án';
  @override
  String get productivity => 'Năng suất';
  @override
  String get crm => 'CRM';
  @override
  String get payments => 'Thanh toán';
  @override
  String get finance => 'Tài chính';
  @override
  String get design => 'Thiết kế';
  @override
  String get automation => 'Tự động hóa';
  @override
  String get knowledge => 'Kiến thức';
  @override
  String get maps => 'Bản đồ';
  @override
  String get travel => 'Du lịch';
}

// Path: base.mcpServers.page
class _Translations$base$mcpServers$page$vi extends Translations$base$mcpServers$page$en {
  _Translations$base$mcpServers$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String count({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    zero: '${count} máy chủ',
    one: '${count} máy chủ',
    other: '${count} máy chủ',
  );
  @override
  String get intro => 'Máy chủ MCP cung cấp thêm công cụ cho mô hình, ví dụ để tìm kiếm trên web hoặc làm việc với các dịch vụ khác.';
  @override
  String get privacy =>
      'Mô hình tự quyết định khi nào sử dụng chúng và có thể gửi nội dung từ các đoạn chat và kho lưu trữ của bạn đến các máy chủ. Chỉ thêm những máy chủ bạn tin tưởng.';
  @override
  String get emptyTitle => 'Chưa có máy chủ MCP nào';
  @override
  String get emptyText => 'Thêm máy chủ MCP bằng URL của nó để mô hình có thể sử dụng các công cụ của máy chủ trong các đoạn chat của bạn.';
  @override
  String get emptyTextShared =>
      'Chưa có máy chủ MCP nào được chia sẻ với bạn. Khi có người chia sẻ, bạn có thể bật máy chủ đó tại đây để sử dụng các công cụ của nó trong các đoạn chat của bạn.';
  @override
  String get editServer => 'Chỉnh sửa máy chủ';
  @override
  String get deleteServer => 'Xóa máy chủ';
  @override
  String get authNone => 'Không xác thực';
  @override
  String get authToken => 'Token';
  @override
  String authTokenHint({required Object hint}) => 'Token •••• ${hint}';
  @override
  String get authOAuth => 'Đã đăng nhập bằng OAuth';
  @override
  String checked({required Object relative}) => 'Đã kiểm tra ${relative}';
  @override
  String lastError({required Object error}) => 'Lần kết nối gần nhất thất bại: ${error}';
  @override
  String get lastErrorShared => 'Lần kết nối gần nhất thất bại. Chỉ chủ sở hữu mới xem được lý do.';
  @override
  String get signInRequired =>
      'Máy chủ yêu cầu bạn đăng nhập trước khi có thể sử dụng các công cụ của nó. Nếu máy chủ không hỗ trợ đăng nhập, hãy xóa và thêm lại bằng token.';
  @override
  String get signInRequiredShared => 'Máy chủ yêu cầu chủ sở hữu đăng nhập lại trước khi có thể sử dụng các công cụ của nó.';
  @override
  String toolCount({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    zero: 'Không có công cụ nào',
    one: '1 công cụ',
    other: '${count} công cụ',
  );
  @override
  String toolCountEnabled({required num count, required Object enabled}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    one: 'Đã bật ${enabled}/${count} công cụ',
    other: 'Đã bật ${enabled}/${count} công cụ',
  );
  @override
  String get noTools => 'Máy chủ không cung cấp công cụ nào.';
  @override
  String get allTools => 'Tất cả công cụ';
  @override
  String get signIn => 'Đăng nhập';
  @override
  String get signInAgain => 'Đăng nhập lại';
  @override
  String get useInChats => 'Sử dụng trong đoạn chat';
  @override
  String get notUsed => 'Không sử dụng trong đoạn chat';
  @override
  String sharedBy({required Object name}) => 'Được chia sẻ bởi ${name}';
  @override
  String get sharedWithYouHint => 'Chỉ chủ sở hữu mới có thể thay đổi máy chủ này và các công cụ của nó.';
  @override
  String sharedOff({required Object name}) =>
      '${name} đã chia sẻ máy chủ này với bạn. Các công cụ của nó chỉ được sử dụng trong các đoạn chat của bạn khi bạn bật máy chủ.';
  @override
  String signInTitle({required Object name}) => 'Đăng nhập vào ${name}?';
  @override
  String signInText({required Object name}) =>
      '${name} yêu cầu bạn đăng nhập trước khi có thể sử dụng các công cụ của nó. Bạn sẽ được chuyển đến trang đăng nhập của nó, rồi được đưa trở lại đây.';
  @override
  String get deleteTitle => 'Xóa máy chủ MCP';
  @override
  String deleteText({required Object name}) =>
      'Máy chủ MCP ${name} sẽ bị xóa. Các công cụ của nó sẽ không còn khả dụng trong các đoạn chat của bạn, cũng như của những người dùng mà bạn đã chia sẻ.';
  @override
  String get leave => 'Rời khỏi';
  @override
  String get leaveTitle => 'Rời khỏi máy chủ MCP';
  @override
  String leaveText({required Object name}) =>
      'Bạn sẽ không thể sử dụng các công cụ của ${name} trong các đoạn chat của mình nữa. Chủ sở hữu có thể chia sẻ lại máy chủ với bạn.';
  @override
  String get created => 'Đã thêm máy chủ.';
  @override
  String get updated => 'Đã cập nhật máy chủ.';
  @override
  String get deleted => 'Đã xóa máy chủ.';
  @override
  String left({required Object name}) => 'Bạn đã rời khỏi ${name}.';
  @override
  String enabled({required Object name}) => 'Đã bật ${name}.';
  @override
  String disabled({required Object name}) => 'Đã tắt ${name}.';
  @override
  String toolEnabled({required Object name}) => 'Đã bật công cụ ${name}.';
  @override
  String toolDisabled({required Object name}) => 'Đã tắt công cụ ${name}.';
  @override
  String allToolsEnabled({required Object name}) => 'Đã bật tất cả công cụ của ${name}.';
  @override
  String allToolsDisabled({required Object name}) => 'Đã tắt tất cả công cụ của ${name}.';
  @override
  String refreshed({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    zero: 'Đã kết nối, máy chủ không cung cấp công cụ nào.',
    one: 'Đã kết nối, máy chủ cung cấp 1 công cụ.',
    other: 'Đã kết nối, máy chủ cung cấp ${count} công cụ.',
  );
  @override
  String refreshedSignIn({required Object name}) => '${name} yêu cầu bạn đăng nhập.';
  @override
  String refreshedFailed({required Object name}) => 'Không thể kết nối đến ${name}.';
  @override
  String loadFailed({required Object error}) => 'Không thể tải danh sách máy chủ MCP: ${error}';
  @override
  String createFailed({required Object error}) => 'Không thể thêm máy chủ: ${error}';
  @override
  String saveFailed({required Object error}) => 'Không thể lưu máy chủ: ${error}';
  @override
  String deleteFailed({required Object error}) => 'Không thể xóa máy chủ: ${error}';
  @override
  String leaveFailed({required Object error}) => 'Không thể rời khỏi máy chủ: ${error}';
  @override
  String toggleFailed({required Object error}) => 'Không thể thay đổi máy chủ: ${error}';
  @override
  String toggleToolFailed({required Object error}) => 'Không thể thay đổi công cụ: ${error}';
  @override
  String toggleAllToolsFailed({required Object error}) => 'Không thể thay đổi các công cụ: ${error}';
  @override
  String refreshFailed({required Object error}) => 'Không thể làm mới máy chủ: ${error}';
  @override
  String signInFailed({required Object error}) => 'Không thể bắt đầu đăng nhập: ${error}';
}

// Path: base.mcpServers.dialog
class _Translations$base$mcpServers$dialog$vi extends Translations$base$mcpServers$dialog$en {
  _Translations$base$mcpServers$dialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get editTitle => 'Chỉnh sửa máy chủ';
  @override
  String get url => 'URL';
  @override
  String get urlHintAdmin => 'Endpoint MCP của máy chủ. Với tư cách quản trị viên, bạn cũng có thể dùng http:// và host nội bộ.';
  @override
  String get urlHintUser => 'Endpoint MCP của máy chủ. Phải dùng https:// và một host phân giải thành địa chỉ công khai.';
  @override
  String get tokenOptional => 'Token (không bắt buộc)';
  @override
  String get tokenHint => 'Chỉ dành cho máy chủ yêu cầu token và không hỗ trợ đăng nhập. Được gửi dưới dạng bearer token.';
  @override
  String get fixedConnection => 'Không thể thay đổi URL và token. Để thay đổi, hãy xóa máy chủ và thêm lại.';
  @override
  String get connecting => 'Đang kết nối đến máy chủ, việc này có thể mất vài giây…';
  @override
  String get missingUrl => 'Thiếu URL';
}

// Path: base.mcpServers.sharing
class _Translations$base$mcpServers$sharing$vi extends Translations$base$mcpServers$sharing$en {
  _Translations$base$mcpServers$sharing$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chia sẻ';
  @override
  String get description =>
      'Người dùng được bạn chia sẻ máy chủ này phải bật nó để sử dụng trong các đoạn chat của họ. Họ không thể thay đổi những công cụ nào được bật.';
  @override
  String get notShared => 'Chưa chia sẻ với ai';
  @override
  String sharedAt({required Object relative}) => 'Đã chia sẻ ${relative}';
  @override
  String get share => 'Chia sẻ';
  @override
  String get stopSharing => 'Ngừng chia sẻ';
  @override
  String get stopSharingTitle => 'Ngừng chia sẻ';
  @override
  String stopSharingText({required Object name}) => '${name} sẽ không thể sử dụng các công cụ của máy chủ này trong các đoạn chat của họ nữa.';
  @override
  String get shared => 'Đã chia sẻ máy chủ.';
  @override
  String get unknownUser => 'Không có người dùng nào với tên người dùng hoặc email này';
  @override
  String get stopped => 'Đã ngừng chia sẻ.';
  @override
  String loadFailed({required Object error}) => 'Không thể tải danh sách người dùng: ${error}';
  @override
  String shareFailed({required Object error}) => 'Không thể chia sẻ máy chủ: ${error}';
  @override
  String stopFailed({required Object error}) => 'Không thể ngừng chia sẻ: ${error}';
}

// Path: base.mcpServers.shareDialog
class _Translations$base$mcpServers$shareDialog$vi extends Translations$base$mcpServers$shareDialog$en {
  _Translations$base$mcpServers$shareDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chia sẻ máy chủ MCP';
  @override
  String get description =>
      'Người dùng có thể bật máy chủ này để sử dụng các công cụ đã bật trong các đoạn chat của họ, bằng token hoặc thông tin đăng nhập của bạn, nhưng không thể thay đổi, làm mới hay xóa máy chủ.';
}

// Path: base.mcpServers.callback
class _Translations$base$mcpServers$callback$vi extends Translations$base$mcpServers$callback$en {
  _Translations$base$mcpServers$callback$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Đăng nhập';
  @override
  String get completing => 'Đang hoàn tất đăng nhập…';
  @override
  String get failedTitle => 'Đăng nhập thất bại';
  @override
  String get denied => 'Đăng nhập đã bị hủy hoặc bị từ chối.';
  @override
  String serverError({required Object error}) => 'Máy chủ đã báo lỗi: ${error}';
  @override
  String get incomplete => 'Phản hồi cho yêu cầu đăng nhập không đầy đủ. Vui lòng đăng nhập lại.';
  @override
  String get expired => 'Yêu cầu đăng nhập đã hết hạn hoặc đã được hoàn tất. Vui lòng đăng nhập lại.';
  @override
  String failed({required Object error}) => 'Không thể hoàn tất đăng nhập: ${error}';
  @override
  String signedIn({required Object name}) => 'Đã đăng nhập vào ${name}.';
  @override
  String signedInNotReady({required Object name}) => 'Đã đăng nhập vào ${name}, nhưng không thể kết nối đến máy chủ.';
  @override
  String get back => 'Quay lại danh sách máy chủ MCP';
}

// Path: base.admin.users
class _Translations$base$admin$users$vi extends Translations$base$admin$users$en {
  _Translations$base$admin$users$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Người dùng';
  @override
  String get mustChangePassword => 'Phải đổi mật khẩu';
  @override
  String get chooseOwnPasswordHint => 'Họ sẽ tự chọn mật khẩu riêng sau khi đăng nhập bằng mật khẩu này';
  @override
  late final _Translations$base$admin$users$page$vi page = _Translations$base$admin$users$page$vi._(_root);
  @override
  late final _Translations$base$admin$users$createDialog$vi createDialog = _Translations$base$admin$users$createDialog$vi._(_root);
  @override
  late final _Translations$base$admin$users$editDialog$vi editDialog = _Translations$base$admin$users$editDialog$vi._(_root);
  @override
  late final _Translations$base$admin$users$passwordDialog$vi passwordDialog = _Translations$base$admin$users$passwordDialog$vi._(_root);
  @override
  late final _Translations$base$admin$users$deleteDialog$vi deleteDialog = _Translations$base$admin$users$deleteDialog$vi._(_root);
}

// Path: base.admin.llm
class _Translations$base$admin$llm$vi extends Translations$base$admin$llm$en {
  _Translations$base$admin$llm$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Nhà cung cấp LLM';
  @override
  String get newProvider => 'Nhà cung cấp mới';
  @override
  String get pricePerMillion => 'Giá cho 1 triệu token';
  @override
  late final _Translations$base$admin$llm$page$vi page = _Translations$base$admin$llm$page$vi._(_root);
  @override
  late final _Translations$base$admin$llm$providerDialog$vi providerDialog = _Translations$base$admin$llm$providerDialog$vi._(_root);
  @override
  late final _Translations$base$admin$llm$modelDialog$vi modelDialog = _Translations$base$admin$llm$modelDialog$vi._(_root);
  @override
  late final _Translations$base$admin$llm$remoteModelsDialog$vi remoteModelsDialog = _Translations$base$admin$llm$remoteModelsDialog$vi._(_root);
}

// Path: base.admin.config
class _Translations$base$admin$config$vi extends Translations$base$admin$config$en {
  _Translations$base$admin$config$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Cấu hình';
  @override
  String get overrideAction => 'Ghi đè';
  @override
  late final _Translations$base$admin$config$page$vi page = _Translations$base$admin$config$page$vi._(_root);
  @override
  late final _Translations$base$admin$config$overrideDialog$vi overrideDialog = _Translations$base$admin$config$overrideDialog$vi._(_root);
}

// Path: base.admin.extraction
class _Translations$base$admin$extraction$vi extends Translations$base$admin$extraction$en {
  _Translations$base$admin$extraction$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Trích xuất tài liệu';
  @override
  late final _Translations$base$admin$extraction$page$vi page = _Translations$base$admin$extraction$page$vi._(_root);
}

// Path: base.admin.server
class _Translations$base$admin$server$vi extends Translations$base$admin$server$en {
  _Translations$base$admin$server$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Thông tin máy chủ';
  @override
  late final _Translations$base$admin$server$page$vi page = _Translations$base$admin$server$page$vi._(_root);
}

// Path: flutter.common.unsavedChanges
class _Translations$flutter$common$unsavedChanges$vi extends Translations$flutter$common$unsavedChanges$en {
  _Translations$flutter$common$unsavedChanges$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Bỏ các thay đổi?';
  @override
  String get text => 'Các thay đổi của bạn chưa được lưu.';
  @override
  String get keepEditing => 'Tiếp tục chỉnh sửa';
  @override
  String get discard => 'Bỏ thay đổi';
}

// Path: flutter.chat.page
class _Translations$flutter$chat$page$vi extends Translations$flutter$chat$page$en {
  _Translations$flutter$chat$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get temporaryOff => 'Tắt đoạn chat tạm thời';
}

// Path: flutter.chat.leaveTemporaryDialog
class _Translations$flutter$chat$leaveTemporaryDialog$vi extends Translations$flutter$chat$leaveTemporaryDialog$en {
  _Translations$flutter$chat$leaveTemporaryDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Rời khỏi đoạn chat tạm thời?';
  @override
  String get text =>
      'Đoạn chat tạm thời không có trong danh sách đoạn chat của bạn, nên bạn không thể quay lại đoạn chat này. Nó sẽ bị xóa một ngày sau tin nhắn cuối cùng.';
  @override
  String get leave => 'Rời khỏi';
}

// Path: flutter.chat.assistantMessage
class _Translations$flutter$chat$assistantMessage$vi extends Translations$flutter$chat$assistantMessage$en {
  _Translations$flutter$chat$assistantMessage$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get fitTables => 'Co bảng cho vừa chiều rộng';
  @override
  String get scrollTables => 'Cuộn ngang các bảng rộng';
}

// Path: flutter.chat.markdownContent
class _Translations$flutter$chat$markdownContent$vi extends Translations$flutter$chat$markdownContent$en {
  _Translations$flutter$chat$markdownContent$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String openLinkFailed({required Object link}) => 'Không thể mở ${link}';
}

// Path: flutter.chat.toolCallPage
class _Translations$flutter$chat$toolCallPage$vi extends Translations$flutter$chat$toolCallPage$en {
  _Translations$flutter$chat$toolCallPage$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String commit({required Object sha}) => 'Commit ${sha}';
}

// Path: flutter.chat.fileContent
class _Translations$flutter$chat$fileContent$vi extends Translations$flutter$chat$fileContent$en {
  _Translations$flutter$chat$fileContent$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get cannotShow => 'Không thể hiển thị tệp này trong ứng dụng.';
  @override
  String get saveFailed => 'Không thể lưu tệp.';
}

// Path: flutter.chat.proposedCommitPage
class _Translations$flutter$chat$proposedCommitPage$vi extends Translations$flutter$chat$proposedCommitPage$en {
  _Translations$flutter$chat$proposedCommitPage$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get notApplied => 'Chưa được áp dụng.';
}

// Path: flutter.settings.page
class _Translations$flutter$settings$page$vi extends Translations$flutter$settings$page$en {
  _Translations$flutter$settings$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String version({required Object version}) => 'Phiên bản ${version}';
}

// Path: flutter.settings.changePasswordPage
class _Translations$flutter$settings$changePasswordPage$vi extends Translations$flutter$settings$changePasswordPage$en {
  _Translations$flutter$settings$changePasswordPage$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get intro => 'Bạn phải đổi mật khẩu trước khi có thể tiếp tục.';
}

// Path: flutter.settings.accountSheet
class _Translations$flutter$settings$accountSheet$vi extends Translations$flutter$settings$accountSheet$en {
  _Translations$flutter$settings$accountSheet$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get accounts => 'Tài khoản';
  @override
  String get addAccount => 'Thêm tài khoản';
}

// Path: flutter.settings.preferences
class _Translations$flutter$settings$preferences$vi extends Translations$flutter$settings$preferences$en {
  _Translations$flutter$settings$preferences$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get deviceDefault => 'Mặc định của thiết bị';
  @override
  String deviceDefaultWithLocale({required Object locale}) => 'Mặc định của thiết bị (${locale})';
  @override
  late final _Translations$flutter$settings$preferences$modelSheet$vi modelSheet = _Translations$flutter$settings$preferences$modelSheet$vi._(_root);
}

// Path: flutter.repositories.listPage
class _Translations$flutter$repositories$listPage$vi extends Translations$flutter$repositories$listPage$en {
  _Translations$flutter$repositories$listPage$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get addedLocal => 'Đã thêm kho lưu trữ.';
}

// Path: flutter.repositories.page
class _Translations$flutter$repositories$page$vi extends Translations$flutter$repositories$page$en {
  _Translations$flutter$repositories$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String tokenSetWithHint({required Object hint}) => 'Đã đặt (•••• ${hint})';
}

// Path: flutter.repositories.form
class _Translations$flutter$repositories$form$vi extends Translations$flutter$repositories$form$en {
  _Translations$flutter$repositories$form$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get showToken => 'Hiện token';
  @override
  String get hideToken => 'Ẩn token';
}

// Path: flutter.repositories.usersCard
class _Translations$flutter$repositories$usersCard$vi extends Translations$flutter$repositories$usersCard$en {
  _Translations$flutter$repositories$usersCard$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String sharedRelative({required Object relative}) => 'Đã chia sẻ ${relative}';
  @override
  String get canCommitOn => 'Có thể áp dụng các thay đổi mà mô hình đề xuất cho họ';
}

// Path: flutter.mcpServers.page
class _Translations$flutter$mcpServers$page$vi extends Translations$flutter$mcpServers$page$en {
  _Translations$flutter$mcpServers$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get signInBrowserFailed => 'Không thể mở trang đăng nhập.';
}

// Path: flutter.mcpServers.form
class _Translations$flutter$mcpServers$form$vi extends Translations$flutter$mcpServers$form$en {
  _Translations$flutter$mcpServers$form$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get showToken => 'Hiện token';
  @override
  String get hideToken => 'Ẩn token';
}

// Path: flutter.mcpServers.namePicker
class _Translations$flutter$mcpServers$namePicker$vi extends Translations$flutter$mcpServers$namePicker$en {
  _Translations$flutter$mcpServers$namePicker$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chọn máy chủ MCP';
  @override
  String get searchHint => 'Tìm kiếm hoặc nhập tên';
  @override
  String useName({required Object name}) => 'Dùng “${name}”';
}

// Path: flutter.documents.details
class _Translations$flutter$documents$details$vi extends Translations$flutter$documents$details$en {
  _Translations$flutter$documents$details$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get path => 'Đường dẫn';
  @override
  String get started => 'Bắt đầu';
  @override
  String get reason => 'Lý do';
  @override
  String get triedAgain => 'Lần thử lại';
  @override
  String get settingsChanged => 'Cài đặt đã thay đổi: tài liệu sẽ được chuyển đổi lại với cài đặt hiện tại.';
  @override
  String get newDocument => 'Mới: tài liệu chưa được chuyển đổi.';
  @override
  String get convertedEarlier => 'Đã chuyển đổi (cài đặt trước đây)';
  @override
  String failedRelative({required Object relative}) => 'Thất bại ${relative}';
  @override
  String get ocrUsed => 'Các trang được nhận dạng bằng OCR, nên văn bản có thể có lỗi.';
  @override
  String get ocrNotUsed => 'Không';
}

// Path: flutter.format.day
class _Translations$flutter$format$day$vi extends Translations$flutter$format$day$en {
  _Translations$flutter$format$day$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get today => 'Hôm nay';
  @override
  String get yesterday => 'Hôm qua';
}

// Path: flutter.format.relative
class _Translations$flutter$format$relative$vi extends Translations$flutter$format$relative$en {
  _Translations$flutter$format$relative$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get justNow => 'vừa xong';
  @override
  String minutesAgo({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    one: '1 phút trước',
    other: '${count} phút trước',
  );
  @override
  String inMinutes({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    one: 'sau 1 phút',
    other: 'sau ${count} phút',
  );
  @override
  String hoursAgo({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    one: '1 giờ trước',
    other: '${count} giờ trước',
  );
  @override
  String inHours({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    one: 'sau 1 giờ',
    other: 'sau ${count} giờ',
  );
  @override
  String daysAgo({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    one: '1 ngày trước',
    other: '${count} ngày trước',
  );
  @override
  String inDays({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    one: 'sau 1 ngày',
    other: 'sau ${count} ngày',
  );
}

// Path: flutter.admin.users
class _Translations$flutter$admin$users$vi extends Translations$flutter$admin$users$en {
  _Translations$flutter$admin$users$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get showPassword => 'Hiện mật khẩu';
  @override
  String get hidePassword => 'Ẩn mật khẩu';
  @override
  late final _Translations$flutter$admin$users$page$vi page = _Translations$flutter$admin$users$page$vi._(_root);
  @override
  late final _Translations$flutter$admin$users$userPage$vi userPage = _Translations$flutter$admin$users$userPage$vi._(_root);
  @override
  late final _Translations$flutter$admin$users$form$vi form = _Translations$flutter$admin$users$form$vi._(_root);
  @override
  late final _Translations$flutter$admin$users$flags$vi flags = _Translations$flutter$admin$users$flags$vi._(_root);
}

// Path: flutter.admin.llm
class _Translations$flutter$admin$llm$vi extends Translations$flutter$admin$llm$en {
  _Translations$flutter$admin$llm$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$admin$llm$page$vi page = _Translations$flutter$admin$llm$page$vi._(_root);
  @override
  late final _Translations$flutter$admin$llm$namePicker$vi namePicker = _Translations$flutter$admin$llm$namePicker$vi._(_root);
  @override
  late final _Translations$flutter$admin$llm$providerForm$vi providerForm = _Translations$flutter$admin$llm$providerForm$vi._(_root);
  @override
  late final _Translations$flutter$admin$llm$modelForm$vi modelForm = _Translations$flutter$admin$llm$modelForm$vi._(_root);
}

// Path: flutter.admin.config
class _Translations$flutter$admin$config$vi extends Translations$flutter$admin$config$en {
  _Translations$flutter$admin$config$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$admin$config$page$vi page = _Translations$flutter$admin$config$page$vi._(_root);
  @override
  late final _Translations$flutter$admin$config$overrideDialog$vi overrideDialog = _Translations$flutter$admin$config$overrideDialog$vi._(_root);
  @override
  late final _Translations$flutter$admin$config$mistralKeySheet$vi mistralKeySheet = _Translations$flutter$admin$config$mistralKeySheet$vi._(_root);
}

// Path: flutter.admin.extraction
class _Translations$flutter$admin$extraction$vi extends Translations$flutter$admin$extraction$en {
  _Translations$flutter$admin$extraction$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$flutter$admin$extraction$page$vi page = _Translations$flutter$admin$extraction$page$vi._(_root);
}

// Path: base.settings.account.page
class _Translations$base$settings$account$page$vi extends Translations$base$settings$account$page$en {
  _Translations$base$settings$account$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get memberSince => 'Thành viên từ';
  @override
  String get userNameSaved => 'Đã lưu tên người dùng';
  @override
  String get emailSaved => 'Đã lưu email';
  @override
  String get passwordChanged => 'Đã đổi mật khẩu. Các phiên khác của bạn đã bị đăng xuất.';
  @override
  String userNameSaveFailed({required Object error}) => 'Không thể lưu tên người dùng: ${error}';
  @override
  String emailSaveFailed({required Object error}) => 'Không thể lưu email: ${error}';
  @override
  String changePasswordFailed({required Object error}) => 'Không thể đổi mật khẩu: ${error}';
}

// Path: base.settings.account.changePasswordDialog
class _Translations$base$settings$account$changePasswordDialog$vi extends Translations$base$settings$account$changePasswordDialog$en {
  _Translations$base$settings$account$changePasswordDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Đổi mật khẩu';
  @override
  String get signOutNote => 'Tất cả các phiên khác của bạn sẽ bị đăng xuất.';
  @override
  String get fillAll => 'Vui lòng điền tất cả các trường.';
}

// Path: base.settings.account.userNameDialog
class _Translations$base$settings$account$userNameDialog$vi extends Translations$base$settings$account$userNameDialog$en {
  _Translations$base$settings$account$userNameDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Đổi tên người dùng';
}

// Path: base.settings.account.emailDialog
class _Translations$base$settings$account$emailDialog$vi extends Translations$base$settings$account$emailDialog$en {
  _Translations$base$settings$account$emailDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Đổi email';
}

// Path: base.settings.profile.page
class _Translations$base$settings$profile$page$vi extends Translations$base$settings$profile$page$en {
  _Translations$base$settings$profile$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get description => 'Những thông tin về bạn được cung cấp cho trợ lý, để trợ lý biết "tôi" trong câu hỏi của bạn là ai.';
  @override
  String get fullNameSaved => 'Đã lưu họ và tên';
  @override
  String get firstNameSaved => 'Đã lưu tên';
  @override
  String get aboutSaved => 'Đã lưu phần giới thiệu';
  @override
  String fullNameSaveFailed({required Object error}) => 'Không thể lưu họ và tên: ${error}';
  @override
  String firstNameSaveFailed({required Object error}) => 'Không thể lưu tên: ${error}';
  @override
  String aboutSaveFailed({required Object error}) => 'Không thể lưu phần giới thiệu: ${error}';
}

// Path: base.settings.profile.fullNameDialog
class _Translations$base$settings$profile$fullNameDialog$vi extends Translations$base$settings$profile$fullNameDialog$en {
  _Translations$base$settings$profile$fullNameDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Đổi họ và tên';
  @override
  String get hint => 'Như được ghi trong tài liệu';
  @override
  String tooLong({required Object max}) => 'Họ và tên tối đa ${max} ký tự.';
}

// Path: base.settings.profile.firstNameDialog
class _Translations$base$settings$profile$firstNameDialog$vi extends Translations$base$settings$profile$firstNameDialog$en {
  _Translations$base$settings$profile$firstNameDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Đổi tên';
  @override
  String tooLong({required Object max}) => 'Tên tối đa ${max} ký tự.';
}

// Path: base.settings.profile.aboutDialog
class _Translations$base$settings$profile$aboutDialog$vi extends Translations$base$settings$profile$aboutDialog$en {
  _Translations$base$settings$profile$aboutDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Đổi phần giới thiệu';
  @override
  String get placeholder => 'Ví dụ: vai trò của bạn, các dự án bạn đang làm, hoặc cách bạn muốn được trả lời.';
  @override
  String tooLong({required Object max}) => 'Phần giới thiệu tối đa ${max} ký tự.';
}

// Path: base.settings.preferences.page
class _Translations$base$settings$preferences$page$vi extends Translations$base$settings$preferences$page$en {
  _Translations$base$settings$preferences$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get noModels => 'Chưa cấu hình mô hình nào';
  @override
  String get noModelsAskAdmin => 'Chưa cấu hình mô hình nào. Hãy nhờ quản trị viên thêm một mô hình.';
  @override
  String get modelUpdated => 'Đã cập nhật mô hình.';
  @override
  String get languageUpdated => 'Đã cập nhật ngôn ngữ.';
  @override
  String get autoCommit => 'Tự động áp dụng thay đổi';
  @override
  String get autoCommitHint => 'Các thay đổi do trợ lý đề xuất sẽ được áp dụng ngay khi câu trả lời hoàn tất.';
  @override
  String get autoCommitOn => 'Các thay đổi được đề xuất giờ sẽ được áp dụng tự động.';
  @override
  String get autoCommitOff => 'Các thay đổi được đề xuất giờ sẽ chờ bạn áp dụng.';
  @override
  String modelsLoadFailed({required Object error}) => 'Không thể tải danh sách mô hình: ${error}';
  @override
  String modelSaveFailed({required Object error}) => 'Không thể lưu mô hình: ${error}';
  @override
  String languageSaveFailed({required Object error}) => 'Không thể lưu ngôn ngữ: ${error}';
  @override
  String autoCommitSaveFailed({required Object error}) => 'Không thể lưu cài đặt: ${error}';
}

// Path: base.settings.preferences.localeDialog
class _Translations$base$settings$preferences$localeDialog$vi extends Translations$base$settings$preferences$localeDialog$en {
  _Translations$base$settings$preferences$localeDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chỉnh sửa ngôn ngữ';
  @override
  String get description => 'Ngôn ngữ mô hình dùng để trả lời, đồng thời là ngôn ngữ giao diện nếu giao diện có ngôn ngữ đó.';
  @override
  String get label => 'Ngôn ngữ (BCP 47)';
}

// Path: base.settings.preferences.modelDialog
class _Translations$base$settings$preferences$modelDialog$vi extends Translations$base$settings$preferences$modelDialog$en {
  _Translations$base$settings$preferences$modelDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chỉnh sửa mô hình';
  @override
  String get description => 'Mô hình trả lời các câu hỏi của bạn.';
}

// Path: base.admin.users.page
class _Translations$base$admin$users$page$vi extends Translations$base$admin$users$page$en {
  _Translations$base$admin$users$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String count({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    zero: '${count} người dùng',
    one: '${count} người dùng',
    other: '${count} người dùng',
  );
  @override
  String get description =>
      'Mỗi người dùng có các đoạn chat riêng và, nếu được phép, các kho lưu trữ riêng. Nhà cung cấp LLM và mô hình do quản trị viên thiết lập và dùng chung cho mọi người.';
  @override
  String get newUser => 'Người dùng mới';
  @override
  String get user => 'Người dùng';
  @override
  String get identity => 'Danh tính';
  @override
  String get noUsers => 'Không có người dùng nào';
  @override
  String get loginDisabled => 'Đã tắt đăng nhập';
  @override
  String get passwordChangeRequired => 'Cần đổi mật khẩu';
  @override
  String get manage => 'Quản lý';
  @override
  String get readOnly => 'Chỉ đọc';
  @override
  String get useOnly => 'Chỉ sử dụng';
  @override
  String get editable => 'Có thể sửa';
  @override
  String get fixed => 'Cố định';
  @override
  String get cannotDeleteSelf => 'Bạn không thể xóa chính mình';
  @override
  String get cannotDeleteAdmin => 'Không thể xóa quản trị viên';
  @override
  String get setPassword => 'Đặt mật khẩu';
  @override
  String get cannotSetOwnPassword => 'Hãy đổi mật khẩu của bạn trong cài đặt tài khoản';
  @override
  String get created => 'Đã tạo người dùng.';
  @override
  String get updated => 'Đã cập nhật người dùng.';
  @override
  String get passwordSet => 'Đã đặt mật khẩu.';
  @override
  String get deleted => 'Đã xóa người dùng.';
  @override
  String loadFailed({required Object error}) => 'Không thể tải danh sách người dùng: ${error}';
  @override
  String createFailed({required Object error}) => 'Không thể tạo người dùng: ${error}';
  @override
  String saveFailed({required Object error}) => 'Không thể lưu người dùng: ${error}';
  @override
  String setPasswordFailed({required Object error}) => 'Không thể đặt mật khẩu: ${error}';
  @override
  String deleteFailed({required Object error}) => 'Không thể xóa người dùng: ${error}';
}

// Path: base.admin.users.createDialog
class _Translations$base$admin$users$createDialog$vi extends Translations$base$admin$users$createDialog$en {
  _Translations$base$admin$users$createDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Tạo người dùng';
}

// Path: base.admin.users.editDialog
class _Translations$base$admin$users$editDialog$vi extends Translations$base$admin$users$editDialog$en {
  _Translations$base$admin$users$editDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chỉnh sửa người dùng';
  @override
  String get adminUnrestricted => 'Không thể hạn chế quyền của quản trị viên';
  @override
  String get canLogin => 'Có thể đăng nhập';
  @override
  String get canLoginHint => 'Tắt tùy chọn này sẽ đăng xuất người dùng trên mọi thiết bị';
  @override
  String get canManageRepositories => 'Có thể quản lý kho lưu trữ';
  @override
  String get canManageRepositoriesHint =>
      'Nếu không có quyền này, trang Kho lưu trữ sẽ bị ẩn và họ chỉ có thể hỏi về các kho lưu trữ được chia sẻ với họ';
  @override
  String get canManageMcpServers => 'Có thể quản lý máy chủ MCP';
  @override
  String get canManageMcpServersHint => 'Nếu không có quyền này, trang Máy chủ MCP sẽ bị ẩn và họ không thể thêm hoặc thay đổi máy chủ MCP';
  @override
  String get canChangeIdentity => 'Có thể đổi tên người dùng và email';
  @override
  String get canChangeIdentityHint => 'Nếu không có quyền này, chỉ quản trị viên mới có thể thay đổi chúng';
  @override
  String get mustChangePasswordHint => 'Cho đến khi đổi mật khẩu, người dùng không thể làm gì khác sau khi đăng nhập';
}

// Path: base.admin.users.passwordDialog
class _Translations$base$admin$users$passwordDialog$vi extends Translations$base$admin$users$passwordDialog$en {
  _Translations$base$admin$users$passwordDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Đặt mật khẩu';
  @override
  String intro({required Object name}) => 'Đặt mật khẩu mới cho ${name} và đăng xuất họ trên mọi thiết bị.';
}

// Path: base.admin.users.deleteDialog
class _Translations$base$admin$users$deleteDialog$vi extends Translations$base$admin$users$deleteDialog$en {
  _Translations$base$admin$users$deleteDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Xóa người dùng';
  @override
  String get intro => 'Người dùng này sẽ bị xóa:';
  @override
  String get consequences =>
      'Các phiên, đoạn chat và kho lưu trữ của họ cũng sẽ bị xóa. Các kho lưu trữ họ sở hữu cũng sẽ bị gỡ khỏi tất cả những người đã được chia sẻ.';
}

// Path: base.admin.llm.page
class _Translations$base$admin$llm$page$vi extends Translations$base$admin$llm$page$en {
  _Translations$base$admin$llm$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String count({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    zero: '${count} mô hình',
    one: '${count} mô hình',
    other: '${count} mô hình',
  );
  @override
  String get providerIntro =>
      'Nhà cung cấp là một máy chủ LLM: API của Anthropic, hoặc bất kỳ máy chủ nào tương thích với OpenAI như OpenRouter, Ollama, vLLM hay LM Studio.';
  @override
  String get modelsIntro => 'Mỗi mô hình thuộc về một nhà cung cấp và phải hỗ trợ streaming cũng như gọi công cụ.';
  @override
  String defaultIntro({required Object icon}) => 'Mô hình mặc định (${icon}) trả lời những người dùng chưa chọn mô hình trong cài đặt của họ.';
  @override
  String get emptyTitle => 'Chưa có nhà cung cấp nào';
  @override
  String get emptyText =>
      'Không ai có thể đặt câu hỏi cho đến khi có một mô hình được thiết lập. Mô hình đầu tiên bạn thêm sẽ trở thành mô hình mặc định.';
  @override
  String get noModels => 'Hãy thêm mô hình cho một nhà cung cấp. Khi chưa có mô hình nào, không ai có thể đặt câu hỏi.';
  @override
  String noDefault({required Object icon}) =>
      'Hiện không có mô hình mặc định. Người dùng chưa chọn mô hình trong cài đặt của họ sẽ không thể đặt câu hỏi cho đến khi bạn đặt một mô hình làm mặc định (${icon}).';
  @override
  String get editProvider => 'Chỉnh sửa nhà cung cấp';
  @override
  String get deleteProvider => 'Xóa nhà cung cấp';
  @override
  String get defaultModel => 'Mô hình mặc định';
  @override
  String get makeDefault => 'Đặt làm mặc định';
  @override
  String price({required Object input, required Object output}) => '${input} đầu vào / ${output} đầu ra';
  @override
  String cachePrices({required Object read, required Object write}) => 'Đọc bộ nhớ đệm ${read}, ghi bộ nhớ đệm ${write}';
  @override
  String get notSet => 'Chưa đặt';
  @override
  String get editModel => 'Chỉnh sửa mô hình';
  @override
  String get deleteModel => 'Xóa mô hình';
  @override
  String get noModelsYet => 'Chưa có mô hình nào.';
  @override
  String get fetchModels => 'Lấy danh sách mô hình';
  @override
  String get addModel => 'Thêm mô hình';
  @override
  String get deleteProviderTitle => 'Xóa nhà cung cấp';
  @override
  String deleteProviderText({required num count, required Object name}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    one: 'Nhà cung cấp ${name} sẽ bị xóa cùng với mô hình của nó. Người dùng đã chọn mô hình đó sẽ chuyển về dùng mô hình mặc định.',
    other: 'Nhà cung cấp ${name} sẽ bị xóa cùng với ${count} mô hình của nó. Người dùng đã chọn một trong số đó sẽ chuyển về dùng mô hình mặc định.',
  );
  @override
  String get deleteProviderHasDefault => 'Nhà cung cấp này có mô hình mặc định, nên sau đó sẽ không còn mô hình mặc định nào.';
  @override
  String get deleteModelTitle => 'Xóa mô hình';
  @override
  String deleteModelText({required Object name}) => 'Mô hình ${name} sẽ bị xóa. Người dùng đã chọn mô hình này sẽ chuyển về dùng mô hình mặc định.';
  @override
  String get deleteModelIsDefault => 'Đây là mô hình mặc định, nên sau đó sẽ không còn mô hình mặc định nào.';
  @override
  String get kContinue => 'Tiếp tục?';
  @override
  String get providerUpdated => 'Đã cập nhật nhà cung cấp.';
  @override
  String get providerCreated => 'Đã tạo nhà cung cấp.';
  @override
  String get providerDeleted => 'Đã xóa nhà cung cấp.';
  @override
  String get modelUpdated => 'Đã cập nhật mô hình.';
  @override
  String modelsAdded({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    one: 'Đã thêm mô hình.',
    other: 'Đã thêm ${count} mô hình.',
  );
  @override
  String get modelDeleted => 'Đã xóa mô hình.';
  @override
  String partlyAdded({required Object added, required Object total, required Object error}) => 'Đã thêm ${added} trong số ${total} mô hình. ${error}';
  @override
  String partlyAddedMore({required Object added, required Object total, required Object error, required Object more}) =>
      'Đã thêm ${added} trong số ${total} mô hình. ${error} (và ${more} lỗi khác)';
  @override
  String get defaultChanged => 'Đã thay đổi mô hình mặc định.';
  @override
  String loadFailed({required Object error}) => 'Không thể tải danh sách nhà cung cấp: ${error}';
  @override
  String createProviderFailed({required Object error}) => 'Không thể tạo nhà cung cấp: ${error}';
  @override
  String saveProviderFailed({required Object error}) => 'Không thể lưu nhà cung cấp: ${error}';
  @override
  String deleteProviderFailed({required Object error}) => 'Không thể xóa nhà cung cấp: ${error}';
  @override
  String addModelFailed({required Object error}) => 'Không thể thêm mô hình: ${error}';
  @override
  String saveModelFailed({required Object error}) => 'Không thể lưu mô hình: ${error}';
  @override
  String deleteModelFailed({required Object error}) => 'Không thể xóa mô hình: ${error}';
  @override
  String setDefaultFailed({required Object error}) => 'Không thể thay đổi mô hình mặc định: ${error}';
}

// Path: base.admin.llm.providerDialog
class _Translations$base$admin$llm$providerDialog$vi extends Translations$base$admin$llm$providerDialog$en {
  _Translations$base$admin$llm$providerDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get editTitle => 'Chỉnh sửa nhà cung cấp';
  @override
  String get apiFormat => 'Định dạng API';
  @override
  String get currency => 'Tiền tệ';
  @override
  String get baseUrl => 'URL cơ sở';
  @override
  String get apiKey => 'Khóa API';
  @override
  String currentKey({required Object key}) => '(hiện tại: ${key})';
  @override
  String get keyNone => 'không có';
  @override
  String get keySet => 'đã đặt';
  @override
  String get keepKey => 'Giữ khóa hiện tại';
  @override
  String get removeKey => 'Xóa khóa';
  @override
  String get noKey => 'Không dùng khóa';
  @override
  String get setKey => 'Đặt khóa mới';
  @override
  String get newKey => 'Khóa API mới';
  @override
  String get hostChanged =>
      'URL cơ sở giờ trỏ đến một host khác, nên không thể giữ khóa hiện tại. Hãy đặt khóa mới, hoặc xóa khóa nếu máy chủ mới không cần khóa.';
  @override
  String get thirdParty => 'Máy chủ của bên thứ ba';
  @override
  String nameLength({required Object max}) => 'Từ 1 đến ${max} ký tự.';
  @override
  String get missingApiKey => 'Thiếu khóa API';
}

// Path: base.admin.llm.modelDialog
class _Translations$base$admin$llm$modelDialog$vi extends Translations$base$admin$llm$modelDialog$en {
  _Translations$base$admin$llm$modelDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get editTitle => 'Chỉnh sửa mô hình';
  @override
  String newTitle({required Object provider}) => 'Mô hình mới cho ${provider}';
  @override
  String get apiName => 'Tên API';
  @override
  String get displayName => 'Tên hiển thị';
  @override
  String get maxOutputTokens => 'Số token đầu ra tối đa';
  @override
  String get noCurrency => 'Nhà cung cấp chưa có tiền tệ, nên các mô hình của nó không có giá. Hãy đặt tiền tệ cho nhà cung cấp để nhập giá.';
  @override
  String get priceHint => 'Hiển thị chi phí của mỗi câu trả lời. Để trống đầu vào và đầu ra nếu không muốn hiển thị.';
  @override
  String get cacheRead => 'Đọc bộ nhớ đệm';
  @override
  String get cacheWrite => 'Ghi bộ nhớ đệm';
  @override
  String get sameAsInput => 'Giống đầu vào';
  @override
  String get becomesDefault => 'Chưa có mô hình mặc định, nên mô hình này sẽ trở thành mặc định.';
  @override
  String get tokensInvalid => 'Phải là số nguyên dương.';
  @override
  String priceInvalid({required Object max, required Object decimals}) => 'Số không quá ${max}, tối đa ${decimals} chữ số thập phân.';
  @override
  String get missingApiName => 'Thiếu tên API';
  @override
  String apiNameTooLong({required Object max}) => 'Tên API tối đa ${max} ký tự';
  @override
  String displayNameTooLong({required Object max}) => 'Tên hiển thị tối đa ${max} ký tự';
  @override
  String get maxOutputTokensInvalid => 'Số token đầu ra tối đa phải là số nguyên dương';
  @override
  String pricesInvalid({required Object max, required Object decimals}) => 'Giá phải là số không quá ${max}, tối đa ${decimals} chữ số thập phân';
  @override
  String get inputOutputBoth => 'Hãy đặt cả giá đầu vào và đầu ra, hoặc để trống cả hai';
  @override
  String get cacheRequiresPrices => 'Giá bộ nhớ đệm cần có giá đầu vào và đầu ra';
}

// Path: base.admin.llm.remoteModelsDialog
class _Translations$base$admin$llm$remoteModelsDialog$vi extends Translations$base$admin$llm$remoteModelsDialog$en {
  _Translations$base$admin$llm$remoteModelsDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'Mô hình của ${name}';
  @override
  String get fetching => 'Đang lấy danh sách mô hình từ máy chủ…';
  @override
  String get addByNameHint => 'Bạn vẫn có thể thêm mô hình theo tên.';
  @override
  String get noModels => 'Máy chủ không liệt kê mô hình nào.';
  @override
  String get intro => 'Chọn các mô hình cần thêm.';
  @override
  String get selectAll => 'Chọn tất cả';
  @override
  String selectAllMatches({required Object count}) => 'Chọn tất cả ${count} kết quả khớp';
  @override
  String noMatch({required Object query}) => 'Không có mô hình nào khớp với “${query}”.';
  @override
  String get becomesDefault => 'Chưa có mô hình mặc định, nên mô hình đầu tiên được thêm sẽ trở thành mặc định.';
  @override
  String get addByName => 'Thêm theo tên';
  @override
  String addModels({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    zero: 'Thêm mô hình',
    one: 'Thêm 1 mô hình',
    other: 'Thêm ${count} mô hình',
  );
}

// Path: base.admin.config.page
class _Translations$base$admin$config$page$vi extends Translations$base$admin$config$page$en {
  _Translations$base$admin$config$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get stored => 'Các giá trị ghi đè được lưu trong cơ sở dữ liệu, nên vẫn được giữ lại khi máy chủ khởi động lại.';
  @override
  String recommendEnv({required Object envVars}) =>
      'Chúng tôi khuyên bạn dùng ${envVars}, để phần thiết lập được khai báo tập trung ở một nơi. Các giá trị ghi đè chỉ dùng để thử nghiệm nhanh.';
  @override
  String get envVars => 'biến môi trường';
  @override
  String get ocrHint =>
      'Thay đổi cài đặt OCR sẽ chuyển đổi lại tất cả tài liệu, lần lượt từng tài liệu. Trong lúc đó, văn bản trước đây của chúng vẫn được sử dụng.';
  @override
  String get key => 'Khóa';
  @override
  String get env => 'Env';
  @override
  String get kOverride => 'Giá trị ghi đè';
  @override
  String get noConfig => 'Không có cấu hình nào';
  @override
  String get notSet => 'chưa đặt';
  @override
  String get envOnly => 'Chỉ đặt qua env';
  @override
  String get useEnv => 'Dùng giá trị từ env';
  @override
  String get updated => 'Đã cập nhật cấu hình.';
  @override
  String loadFailed({required Object error}) => 'Không thể tải cấu hình: ${error}';
  @override
  String saveFailed({required Object error}) => 'Không thể lưu giá trị ghi đè: ${error}';
}

// Path: base.admin.config.overrideDialog
class _Translations$base$admin$config$overrideDialog$vi extends Translations$base$admin$config$overrideDialog$en {
  _Translations$base$admin$config$overrideDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String env({required Object value}) => 'Env: ${value}';
  @override
  String get value => 'Giá trị';
  @override
  String get clearHint => 'Bỏ chọn để dùng giá trị từ env';
  @override
  String get emptyHint => 'Để trống để dùng giá trị từ env';
}

// Path: base.admin.extraction.page
class _Translations$base$admin$extraction$page$vi extends Translations$base$admin$extraction$page$en {
  _Translations$base$admin$extraction$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String count({required num count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('vi'))(
    count,
    one: '${count} tài liệu',
    other: '${count} tài liệu',
  );
  @override
  String ocrSettings({required Object config}) => 'Cài đặt OCR là một phần của ${config}. Thay đổi chúng sẽ chuyển đổi lại tất cả tài liệu.';
  @override
  String get configLink => 'cấu hình';
  @override
  String get pausedTitle => 'Dịch vụ OCR không khả dụng';
  @override
  String pausedUntil({required Object time}) => 'Việc chuyển đổi được tạm dừng đến ${time}.';
  @override
  String get now => 'Hiện tại';
  @override
  String converting({required Object path, required Object started}) => 'Đang chuyển đổi ${path}, bắt đầu ${started}';
  @override
  String convertingAttachment({required Object path, required Object started}) =>
      'Đang chuyển đổi ${path} (đính kèm trong một đoạn chat), bắt đầu ${started}';
  @override
  String convertingRepository({required Object path, required Object repository, required Object owner, required Object started}) =>
      'Đang chuyển đổi ${path} trong ${repository} (${owner}), bắt đầu ${started}';
  @override
  String get statusPaused => 'Đã tạm dừng';
  @override
  String get statusWaiting => 'Đang chờ tài liệu tiếp theo';
  @override
  String get statusIdle => 'Không hoạt động, không có tài liệu nào đang chờ';
  @override
  String total({required Object count}) => 'Tổng ${count}';
  @override
  String converted({required Object count}) => '${count} đã chuyển đổi';
  @override
  String failed({required Object count}) => '${count} thất bại';
  @override
  String waiting({required Object count}) => '${count} đang chờ';
  @override
  String notAvailable({required Object count}) => '${count} không khả dụng';
  @override
  String get extractor => 'Trình trích xuất';
  @override
  String get convertAgain => 'Chuyển đổi lại';
  @override
  String get retried => 'Tài liệu sẽ được chuyển đổi lại.';
  @override
  String loadFailed({required Object error}) => 'Không thể tải danh sách tài liệu: ${error}';
  @override
  String retryFailed({required Object error}) => 'Không thể chuyển đổi lại tài liệu: ${error}';
}

// Path: base.admin.server.page
class _Translations$base$admin$server$page$vi extends Translations$base$admin$server$page$en {
  _Translations$base$admin$server$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get baseUrl => 'URL cơ sở';
  @override
  String get version => 'Phiên bản máy chủ';
  @override
  String get copied => 'Đã sao chép vào bảng tạm.';
  @override
  String get copyFailed => 'Không thể sao chép vào bảng tạm.';
  @override
  String loadFailed({required Object error}) => 'Không thể tải thông tin máy chủ: ${error}';
}

// Path: flutter.settings.preferences.modelSheet
class _Translations$flutter$settings$preferences$modelSheet$vi extends Translations$flutter$settings$preferences$modelSheet$en {
  _Translations$flutter$settings$preferences$modelSheet$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get noneConfigured => 'Chưa cấu hình';
}

// Path: flutter.admin.users.page
class _Translations$flutter$admin$users$page$vi extends Translations$flutter$admin$users$page$en {
  _Translations$flutter$admin$users$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get localOnly =>
      'Repolupe trên thiết bị này chỉ có một người dùng, nên không thể thêm người dùng. Để chia sẻ đoạn chat và kho lưu trữ với người khác, hãy dùng một máy chủ Repolupe.';
  @override
  String get noMatch => 'Không có người dùng nào khớp với tìm kiếm của bạn.';
}

// Path: flutter.admin.users.userPage
class _Translations$flutter$admin$users$userPage$vi extends Translations$flutter$admin$users$userPage$en {
  _Translations$flutter$admin$users$userPage$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get login => 'Đăng nhập';
  @override
  String get loginAllowed => 'Được phép';
  @override
  String get loginDisabled => 'Đã tắt (đã đăng xuất trên mọi thiết bị)';
  @override
  String get repositoriesManage => 'Có thể quản lý kho lưu trữ của mình và chia sẻ chúng';
  @override
  String get repositoriesReadOnly => 'Chỉ đọc (chỉ có thể hỏi về các kho lưu trữ được chia sẻ với họ)';
  @override
  String get mcpServersManage => 'Có thể quản lý máy chủ của mình';
  @override
  String get mcpServersUseOnly => 'Chỉ sử dụng (không thể thêm hoặc thay đổi máy chủ nào)';
  @override
  String get identity => 'Tên người dùng và email';
  @override
  String get identityEditable => 'Người dùng có thể thay đổi chúng';
  @override
  String get identityFixed => 'Cố định (chỉ quản trị viên mới có thể thay đổi)';
  @override
  String get passwordMustChange => 'Phải đổi ở lần đăng nhập tiếp theo';
}

// Path: flutter.admin.users.form
class _Translations$flutter$admin$users$form$vi extends Translations$flutter$admin$users$form$en {
  _Translations$flutter$admin$users$form$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get adminNote => 'Quản trị viên có thể được đổi tên, nhưng không bao giờ bị hạn chế quyền.';
  @override
  String get canManageMcpServersHint => 'Nếu không có quyền này, họ không thể thêm hoặc thay đổi máy chủ MCP.';
}

// Path: flutter.admin.users.flags
class _Translations$flutter$admin$users$flags$vi extends Translations$flutter$admin$users$flags$en {
  _Translations$flutter$admin$users$flags$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get repositoriesReadOnly => 'Kho lưu trữ chỉ đọc';
  @override
  String get mcpServersUseOnly => 'Máy chủ MCP chỉ sử dụng';
  @override
  String get identityFixed => 'Tên người dùng và email cố định';
}

// Path: flutter.admin.llm.page
class _Translations$flutter$admin$llm$page$vi extends Translations$flutter$admin$llm$page$en {
  _Translations$flutter$admin$llm$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get apiKeyNone => 'Không có';
  @override
  String get currencyNone => 'Không có (các mô hình của nhà cung cấp này không có giá)';
  @override
  String get models => 'Mô hình';
}

// Path: flutter.admin.llm.namePicker
class _Translations$flutter$admin$llm$namePicker$vi extends Translations$flutter$admin$llm$namePicker$en {
  _Translations$flutter$admin$llm$namePicker$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Chọn nhà cung cấp';
  @override
  String get searchHint => 'Tìm kiếm hoặc nhập tên';
  @override
  String useName({required Object name}) => 'Dùng “${name}”';
}

// Path: flutter.admin.llm.providerForm
class _Translations$flutter$admin$llm$providerForm$vi extends Translations$flutter$admin$llm$providerForm$en {
  _Translations$flutter$admin$llm$providerForm$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get clearCurrency => 'Xóa tiền tệ';
  @override
  String get showKey => 'Hiện khóa';
  @override
  String get hideKey => 'Ẩn khóa';
}

// Path: flutter.admin.llm.modelForm
class _Translations$flutter$admin$llm$modelForm$vi extends Translations$flutter$admin$llm$modelForm$en {
  _Translations$flutter$admin$llm$modelForm$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String apiNameHint({required Object max}) => 'ID mô hình được gửi đến API. Tối đa ${max} ký tự.';
  @override
  String get displayNameOptional => 'Tên hiển thị (không bắt buộc)';
  @override
  String displayNameHint({required Object max}) => 'Hiển thị cho người dùng thay cho tên API. Tối đa ${max} ký tự.';
  @override
  String get maxOutputTokensOptional => 'Số token đầu ra tối đa (không bắt buộc)';
  @override
  String get maxOutputTokensHint => 'Để trống để dùng giá trị mặc định của định dạng API.';
}

// Path: flutter.admin.config.page
class _Translations$flutter$admin$config$page$vi extends Translations$flutter$admin$config$page$en {
  _Translations$flutter$admin$config$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get runtimeOnly => 'Chỉ có thể ghi đè các cài đặt áp dụng ngay; các cài đặt khác cần khởi động lại.';
  @override
  String get runtime => 'Áp dụng ngay';
  @override
  String overrideValue({required Object value}) => 'Giá trị ghi đè: ${value}';
}

// Path: flutter.admin.config.overrideDialog
class _Translations$flutter$admin$config$overrideDialog$vi extends Translations$flutter$admin$config$overrideDialog$en {
  _Translations$flutter$admin$config$overrideDialog$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get remove => 'Xóa giá trị ghi đè';
}

// Path: flutter.admin.config.mistralKeySheet
class _Translations$flutter$admin$config$mistralKeySheet$vi extends Translations$flutter$admin$config$mistralKeySheet$en {
  _Translations$flutter$admin$config$mistralKeySheet$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String get intro => 'Được dùng khi OCR_ENGINE là mistral.';
  @override
  String get remove => 'Xóa khóa';
}

// Path: flutter.admin.extraction.page
class _Translations$flutter$admin$extraction$page$vi extends Translations$flutter$admin$extraction$page$en {
  _Translations$flutter$admin$extraction$page$vi._(TranslationsVi root) : this._root = root, super.internal(root);

  final TranslationsVi _root; // ignore: unused_field

  // Translations
  @override
  String loadMore({required Object remaining}) => 'Tải thêm (còn ${remaining})';
}
