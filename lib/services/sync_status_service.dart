import 'dart:async';

import 'package:flutter/foundation.dart';

enum SyncBannerKind { idle, syncing, success, failed }

enum SyncFailureKind {
  accountSigningFailed,
  accountDisconnected,
  syncFailed,
  syncUnavailableAuth,
}

class SyncBannerState {
  const SyncBannerState({
    required this.kind,
    this.lastSuccessfulAt,
    this.failureKind,
  });

  const SyncBannerState.idle()
      : kind = SyncBannerKind.idle,
        lastSuccessfulAt = null,
        failureKind = null;

  final SyncBannerKind kind;
  final DateTime? lastSuccessfulAt;
  final SyncFailureKind? failureKind;
}

class SyncStatusService {
  SyncStatusService._();

  static final SyncStatusService instance = SyncStatusService._();

  final ValueNotifier<SyncBannerState> state =
      ValueNotifier<SyncBannerState>(const SyncBannerState.idle());

  Timer? _clearTimer;

  void restorePersistentFailure({
    DateTime? lastSuccessfulAt,
    SyncFailureKind failureKind = SyncFailureKind.syncFailed,
  }) {
    showFailure(
      lastSuccessfulAt: lastSuccessfulAt,
      failureKind: failureKind,
    );
  }

  void showSyncing({DateTime? lastSuccessfulAt}) {
    _clearTimer?.cancel();

    // A retry must not hide an existing red warning. The warning remains until
    // the retry actually succeeds (or the user explicitly removes the account).
    if (state.value.kind == SyncBannerKind.failed) return;

    state.value = SyncBannerState(
      kind: SyncBannerKind.syncing,
      lastSuccessfulAt: lastSuccessfulAt,
    );
  }

  void showSuccess(DateTime syncedAt) {
    _clearTimer?.cancel();
    state.value = SyncBannerState(
      kind: SyncBannerKind.success,
      lastSuccessfulAt: syncedAt,
    );
    _clearTimer = Timer(const Duration(milliseconds: 2500), () {
      if (state.value.kind == SyncBannerKind.success) {
        state.value = const SyncBannerState.idle();
      }
    });
  }

  void showFailure({
    DateTime? lastSuccessfulAt,
    SyncFailureKind failureKind = SyncFailureKind.syncFailed,
  }) {
    _clearTimer?.cancel();
    state.value = SyncBannerState(
      kind: SyncBannerKind.failed,
      lastSuccessfulAt: lastSuccessfulAt,
      failureKind: failureKind,
    );
  }

  void clear() {
    _clearTimer?.cancel();
    state.value = const SyncBannerState.idle();
  }
}
