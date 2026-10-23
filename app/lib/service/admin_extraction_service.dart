import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

// What admins do to the document conversion (`/api/v1/document-extraction`): each action calls the API, shows a
// snack bar in any case, and returns whether it succeeded.

/// Converts the document with the content [blobOid] again: a failed one, or one left out for a while. Returns
/// whether it was queued.
class RetryDocumentExtractionAction extends AsyncGlobalActionWithResult<bool> {
  final String blobOid;

  RetryDocumentExtractionAction(this.blobOid);

  @override
  Future<bool> reduce() async {
    try {
      await ref.redux(apiProvider).dispatchAsync(ApiRetryDocumentExtractionAction(blobOid: blobOid));
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.extraction.page.retryFailed(error: e.userMessage)));
      return false;
    }

    ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.extraction.page.retried));
    return true;
  }

  @override
  String toString() => 'RetryDocumentExtractionAction($blobOid)';
}
