import 'dart:async';

import 'package:flutter/foundation.dart';


enum SyncBannerKind { idle, syncing, success, failed }

class SyncBannerState {
  const SyncBannerState({
    required this.kind,
    this.lastSuccessfulAt,
  });

  const SyncBannerState.idle()
      : kind = SyncBannerKind.idle,
        lastSuccessfulAt = null;

  final SyncBannerKind kind;
  final DateTime? lastSuccessfulAt;
}

class SyncStatusService {
  SyncStatusService._();

  static final SyncStatusService instance = SyncStatusService._();

  final ValueNotifier<SyncBannerState> state =
      ValueNotifier<SyncBannerState>(const SyncBannerState.idle());

  Timer? _clearTimer;

  void restorePersistentFailure({DateTime? lastSuccessfulAt}) {
    showFailure(lastSuccessfulAt: lastSuccessfulAt);
  }

  void showSyncing({DateTime? lastSuccessfulAt}) {
    _clearTimer?.cancel();
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

  void showFailure({DateTime? lastSuccessfulAt}) {
    _clearTimer?.cancel();
    state.value = SyncBannerState(
      kind: SyncBannerKind.failed,
      lastSuccessfulAt: lastSuccessfulAt,
    );
  }

  void clear() {
    _clearTimer?.cancel();
    state.value = const SyncBannerState.idle();
  }
}
