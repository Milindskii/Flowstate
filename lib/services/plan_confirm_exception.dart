/// One server-side validation problem for an item of a Build My Day confirm request.
///
/// Mirrors `detail.errors[]` of a 422 from POST /api/v1/tasks/batch-create-and-schedule:
/// `{index, client_ref, field, code, message, title}`. `message` is user-facing and safe to
/// show verbatim (e.g. "“Call mom” is set for 7:00 AM, which has already passed. Choose a new time.").
class PlanConfirmError {
  final int index;
  final String? clientRef;
  final String? field;
  final String code;
  final String message;
  final String? title;

  const PlanConfirmError({
    required this.index,
    this.clientRef,
    this.field,
    required this.code,
    required this.message,
    this.title,
  });

  factory PlanConfirmError.fromJson(Map<String, dynamic> json) =>
      PlanConfirmError(
        index: (json['index'] as num?)?.toInt() ?? -1,
        clientRef: json['client_ref'] as String?,
        field: json['field'] as String?,
        code: json['code'] as String? ?? 'invalid',
        message: json['message'] as String? ?? 'This task could not be saved.',
        title: json['title'] as String?,
      );

  /// True when the user must pick a different time for this item.
  bool get needsNewTime =>
      code == 'explicit_time_in_past' ||
      code == 'invalid_range' ||
      code == 'deadline_before_end' ||
      code == 'locked_without_start';
}

/// Thrown by `AppStateProvider.confirmCandidates` when the plan was NOT saved.
/// Nothing was persisted; the preview must stay open so the user can fix it or retry
/// (retrying with the same `planId` is safe — the server is idempotent per plan).
class PlanConfirmException implements Exception {
  final String message;
  final List<PlanConfirmError> errors;
  final bool
      isValidation; // true => user input needs changing; false => transient (network/server)

  const PlanConfirmException(this.message,
      {this.errors = const [], this.isValidation = false});

  PlanConfirmError? errorFor(String? clientRef) {
    if (clientRef == null) return null;
    for (final e in errors) {
      if (e.clientRef == clientRef) return e;
    }
    return null;
  }

  @override
  String toString() => 'PlanConfirmException($message)';
}
