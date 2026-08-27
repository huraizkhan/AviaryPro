import 'dart:async';

import 'package:flutter/foundation.dart';

enum SyncBannerKind { idle, syncing, success, offline, failed }

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
  bool _offlineAnnounced = false;
  bool _failureDismissedForSession = false;

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
    _offlineAnnounced = false;

    // If the user dismissed a red warning for this app session, background
    // retries stay quiet. A real success may still show the success banner.
    if (_failureDismissedForSession) return;

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
    _offlineAnnounced = false;
    _failureDismissedForSession = false;
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

  void showOffline({DateTime? lastSuccessfulAt}) {
    // Never replace a persistent/dismissed red warning with a temporary
    // offline notice during the same app session.
    if (_failureDismissedForSession ||
        state.value.kind == SyncBannerKind.failed ||
        _offlineAnnounced) {
      return;
    }

    _clearTimer?.cancel();
    _offlineAnnounced = true;
    state.value = SyncBannerState(
      kind: SyncBannerKind.offline,
      lastSuccessfulAt: lastSuccessfulAt,
    );
    _clearTimer = Timer(const Duration(milliseconds: 2500), () {
      if (state.value.kind == SyncBannerKind.offline) {
        state.value = const SyncBannerState.idle();
      }
    });
  }

  void markOnline() {
    _offlineAnnounced = false;
  }

  void showFailure({
    DateTime? lastSuccessfulAt,
    SyncFailureKind failureKind = SyncFailureKind.syncFailed,
  }) {
    _clearTimer?.cancel();
    if (_failureDismissedForSession) return;
    state.value = SyncBannerState(
      kind: SyncBannerKind.failed,
      lastSuccessfulAt: lastSuccessfulAt,
      failureKind: failureKind,
    );
  }

  void dismissFailureForSession() {
    if (state.value.kind != SyncBannerKind.failed) return;
    _clearTimer?.cancel();
    _failureDismissedForSession = true;
    state.value = const SyncBannerState.idle();
  }

  void clear() {
    _clearTimer?.cancel();
    _failureDismissedForSession = false;
    state.value = const SyncBannerState.idle();
  }
}
