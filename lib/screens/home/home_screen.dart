import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../birds/add_bird_screen.dart';
import '../birds/birds_screen.dart';
import '../breeding/breeding_screen.dart';
import '../breeding/add_egg_screen.dart';
import '../breeding/select_cage_for_pair_screen.dart';
import '../cages/add_cage_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../finance/add_transaction_screen.dart';
import '../finance/finance_screen.dart';
import '../settings/settings_screen.dart';
import '../search/global_search_screen.dart';
import '../../services/google_drive_backup_service.dart';
import '../../services/google_drive_sync_service.dart';
import '../../services/notification_service.dart';
import '../../services/sync_status_service.dart';
import '../../providers/bird_provider.dart';
import '../../ui/aviary_design.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int selectedIndex = 0;
  int breedingRefreshToken = 0;
  int dashboardRefreshToken = 0;
  late final AnimationController _menuController;
  late final PageController _pageController;
  Timer? _syncTimer;
  Timer? _backupTimer;
  bool _cloudMaintenanceRunning = false;
  final DateFormat _syncTimeFormat = DateFormat('h:mm a');

  static const _pageTitles = [
    'Dashboard',
    'Birds',
    'Breeding',
    'Finance',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: selectedIndex);
    _menuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.instance.syncFromDatabase();
      _initializeCloud();
    });
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _runCloudMaintenance();
    });
    _backupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _runCloudMaintenance(checkBackup: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    _backupTimer?.cancel();
    _pageController.dispose();
    _menuController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService.instance.syncFromDatabase();
      _initializeCloud();
      if (mounted) {
        setState(() => dashboardRefreshToken++);
      }
    }
  }

  Future<void> _initializeCloud() async {
    final syncService = GoogleDriveSyncService.instance;
    final previousError = await syncService.lastSyncError;
    if (previousError != null && previousError.trim().isNotEmpty) {
      SyncStatusService.instance.restorePersistentFailure(
        lastSuccessfulAt: await syncService.lastSuccessfulSyncAt,
        failureKind:
            await syncService.lastFailureKind ?? SyncFailureKind.syncFailed,
      );
    }

    final backupService = GoogleDriveBackupService.instance;
    final rememberedConnection = await backupService.hasRememberedConnection;
    if (rememberedConnection) {
      try {
        await backupService.restorePreviousSession();
        if (backupService.currentEmail == null) {
          await syncService.recordAccountRestoreFailure(
            await backupService.lastAuthError,
          );
        } else {
          await syncService.clearResolvedAccountFailure();
        }
      } catch (error) {
        await syncService.recordAccountSigningFailure(error);
      }
    }
    await _runCloudMaintenance(
      bootstrapEmptyDevice: true,
      checkBackup: true,
    );
  }

  Future<void> _runCloudMaintenance({
    bool bootstrapEmptyDevice = false,
    bool checkBackup = false,
  }) async {
    if (_cloudMaintenanceRunning) return;
    _cloudMaintenanceRunning = true;
    try {
      SyncResult? syncResult;
      if (bootstrapEmptyDevice) {
        syncResult = await GoogleDriveSyncService.instance
            .bootstrapEmptyDeviceFromCloud();
      }
      syncResult ??=
          await GoogleDriveSyncService.instance.runAutomaticSync();

      // Backups stay separate from edit-sync. They are only checked on startup,
      // resume and the slower backup timer.
      if (checkBackup) {
        await GoogleDriveBackupService.instance.runAutomaticBackupIfDue();
      }

      if ((syncResult?.downloadedChanges ?? 0) > 0 && mounted) {
        await context.read<BirdProvider>().loadBirds();
        await NotificationService.instance.syncFromDatabase();
        if (!mounted) return;
        setState(() {
          dashboardRefreshToken++;
          breedingRefreshToken++;
        });
      }
    } catch (_) {
      // Background cloud maintenance never interrupts normal app use.
    } finally {
      _cloudMaintenanceRunning = false;
    }
  }

  bool get _menuIsOpen => !_menuController.isDismissed;

  void _selectTab(int index) {
    _closeAddMenu();
    if (!mounted || index < 0 || index >= _pageTitles.length) return;
    if (selectedIndex != index) {
      setState(() {
        selectedIndex = index;
        if (index == 0) dashboardRefreshToken++;
        if (index == 2) breedingRefreshToken++;
      });
    } else if (index == 0) {
      setState(() => dashboardRefreshToken++);
    } else if (index == 2) {
      setState(() => breedingRefreshToken++);
    }
    if (_pageController.hasClients &&
        (_pageController.page?.round() ?? selectedIndex) != index) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onPageChanged(int index) {
    if (!mounted || selectedIndex == index) return;
    _closeAddMenu();
    setState(() {
      selectedIndex = index;
      if (index == 0) dashboardRefreshToken++;
      if (index == 2) breedingRefreshToken++;
    });
  }

  Future<void> _refreshDashboardAndNotifications() async {
    await NotificationService.instance.syncFromDatabase();
    if (!mounted) return;
    setState(() => dashboardRefreshToken++);
  }

  void _toggleAddMenu() {
    if (_menuIsOpen) {
      _menuController.reverse();
    } else {
      _menuController.forward();
    }
  }

  Future<void> _closeAddMenu() async {
    if (_menuIsOpen) {
      await _menuController.reverse();
    }
  }

  Future<void> _openAddBird() async {
    await _closeAddMenu();
    if (!mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddBirdScreen()),
    );

    if (!mounted) return;
    if (result == true) {
      _selectTab(1);
      await _refreshDashboardAndNotifications();
    }
  }

  Future<void> _openAddCage() async {
    await _closeAddMenu();
    if (!mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddCageScreen()),
    );
    if (result == true) {
      await _refreshDashboardAndNotifications();
    }
  }

  Future<void> _openCreatePair() async {
    await _closeAddMenu();
    if (!mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const SelectCageForPairScreen(),
      ),
    );

    if (!mounted) return;
    if (result == true) {
      setState(() => breedingRefreshToken++);
      _selectTab(2);
      await _refreshDashboardAndNotifications();
    }
  }

  Future<void> _openAddEgg() async {
    await _closeAddMenu();
    if (!mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddEggScreen(),
      ),
    );

    if (!mounted) return;
    if (result == true) {
      setState(() => breedingRefreshToken++);
      _selectTab(2);
      await _refreshDashboardAndNotifications();
    }
  }

  Future<void> _openTransaction(String type) async {
    await _closeAddMenu();
    if (!mounted) return;

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(initialType: type),
      ),
    );

    if (!mounted || changed != true) return;
    _selectTab(3);
    await _refreshDashboardAndNotifications();
  }

  Widget _buildAddOption({
    required int index,
    required String label,
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    final start = index * 0.06;
    final end = 0.68 + (index * 0.05);

    final movement = CurvedAnimation(
      parent: _menuController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
      reverseCurve: Interval(start, end, curve: Curves.easeInCubic),
    );

    final scale = Tween<double>(begin: 0.65, end: 1).animate(movement);

    return AnimatedBuilder(
      animation: movement,
      builder: (context, child) {
        return Positioned(
          right: 0,
          bottom: 62.0 * (index + 1) * movement.value,
          child: IgnorePointer(
            ignoring: movement.value < 0.5,
            child: Opacity(
              opacity: movement.value,
              child: ScaleTransition(
                scale: scale,
                alignment: Alignment.bottomRight,
                child: child,
              ),
            ),
          ),
        );
      },
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        elevation: 5,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .18),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: SizedBox(
            width: 205,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: icon,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddMenu() {
    return SizedBox(
      width: 220,
      height: 430,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomRight,
        children: [
          _buildAddOption(
            index: 0,
            label: 'Bird',
            icon: const AviaryIcon(AviaryIconType.bird, size: 20),
            onPressed: _openAddBird,
          ),
          _buildAddOption(
            index: 1,
            label: 'Create Pair',
            icon: const AviaryIcon(AviaryIconType.pair, size: 21),
            onPressed: _openCreatePair,
          ),
          _buildAddOption(
            index: 2,
            label: 'Cage',
            icon: const AviaryIcon(AviaryIconType.cage, size: 21),
            onPressed: _openAddCage,
          ),
          _buildAddOption(
            index: 3,
            label: 'Egg',
            icon: const AviaryIcon(AviaryIconType.egg, size: 21),
            onPressed: _openAddEgg,
          ),
          _buildAddOption(
            index: 4,
            label: 'Income',
            icon: const AviaryIcon(AviaryIconType.finance, size: 21),
            onPressed: () => _openTransaction('Income'),
          ),
          _buildAddOption(
            index: 5,
            label: 'Expense',
            icon: const Icon(Icons.money_off, size: 21),
            onPressed: () => _openTransaction('Expense'),
          ),
          FloatingActionButton(
            heroTag: 'main_add_button',
            onPressed: _toggleAddMenu,
            child: AnimatedBuilder(
              animation: _menuController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _menuController.value * 0.785398,
                  child: child,
                );
              },
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncBanner() {
    return ValueListenableBuilder<SyncBannerState>(
      valueListenable: SyncStatusService.instance.state,
      builder: (context, state, _) {
        if (state.kind == SyncBannerKind.idle) {
          return const SizedBox.shrink();
        }

        final scheme = Theme.of(context).colorScheme;
        final lastSync = state.lastSuccessfulAt;
        final String text;
        final Color background;
        final Color foreground;
        final IconData icon;

        switch (state.kind) {
          case SyncBannerKind.syncing:
            text = 'Syncing.....';
            background = scheme.surfaceContainerHigh;
            foreground = scheme.onSurface;
            icon = Icons.sync;
            break;
          case SyncBannerKind.success:
            text = 'Synced successfully · ${_syncTimeFormat.format(lastSync!)}';
            background = scheme.primaryContainer;
            foreground = scheme.onPrimaryContainer;
            icon = Icons.cloud_done_outlined;
            break;
          case SyncBannerKind.failed:
            switch (state.failureKind ?? SyncFailureKind.syncFailed) {
              case SyncFailureKind.accountSigningFailed:
                text = 'Account signing failed · Sign in again';
                icon = Icons.account_circle_outlined;
                break;
              case SyncFailureKind.accountDisconnected:
                text = 'Account disconnected unexpectedly · Reconnect';
                icon = Icons.link_off;
                break;
              case SyncFailureKind.syncUnavailableAuth:
                text = 'Sync unavailable · Account authentication failed';
                icon = Icons.no_accounts_outlined;
                break;
              case SyncFailureKind.syncFailed:
                text = lastSync == null
                    ? 'Sync failed · No successful sync yet'
                    : 'Sync failed · Last sync ${_syncTimeFormat.format(lastSync)}';
                icon = Icons.sync_problem;
                break;
            }
            background = Colors.red.shade700;
            foreground = Colors.white;
            break;
          case SyncBannerKind.idle:
            return const SizedBox.shrink();
        }

        return Material(
          color: background,
          child: SafeArea(
            top: false,
            bottom: false,
            child: SizedBox(
              height: 40,
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    if (state.kind == SyncBannerKind.syncing)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      )
                    else
                      Icon(icon, size: 19, color: foreground),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: selectedIndex == 0 && !_menuIsOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_menuIsOpen) {
          _closeAddMenu();
          return;
        }
        if (selectedIndex != 0) {
          _selectTab(0);
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_pageTitles[selectedIndex]),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GlobalSearchScreen(),
                ),
              );
            },
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_menuIsOpen) {
            _closeAddMenu();
          }
        },
        child: PageView(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          children: [
            _KeepAlivePage(
              child: AviaryResponsivePane(
                child: DashboardScreen(
                  key: ValueKey('dashboard_$dashboardRefreshToken'),
                  onNavigate: _selectTab,
                ),
              ),
            ),
            const _KeepAlivePage(
              child: AviaryResponsivePane(child: BirdsScreen()),
            ),
            _KeepAlivePage(
              child: AviaryResponsivePane(
                child: BreedingScreen(
                  key: ValueKey('breeding_$breedingRefreshToken'),
                ),
              ),
            ),
            const _KeepAlivePage(
              child: AviaryResponsivePane(child: FinanceScreen()),
            ),
            const _KeepAlivePage(
              child: AviaryResponsivePane(child: SettingsScreen()),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildAddMenu(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSyncBanner(),
          NavigationBarTheme(
            data: Theme.of(context).navigationBarTheme.copyWith(
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final compact = MediaQuery.sizeOf(context).width < 360;
                return TextStyle(
                  fontSize: compact ? 10.5 : 12,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w700
                      : FontWeight.w500,
                );
              }),
            ),
            child: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: _selectTab,
              destinations: [
          NavigationDestination(
            icon: const AviaryIcon(AviaryIconType.dashboard),
            selectedIcon: const AviaryIcon(
              AviaryIconType.dashboard,
              filled: true,
              color: AviaryColors.dashboard,
            ),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: const AviaryIcon(AviaryIconType.bird),
            selectedIcon: const AviaryIcon(
              AviaryIconType.bird,
              filled: true,
              color: AviaryColors.birds,
            ),
            label: 'Birds',
          ),
          NavigationDestination(
            icon: const AviaryIcon(AviaryIconType.breeding),
            selectedIcon: const AviaryIcon(
              AviaryIconType.breeding,
              filled: true,
              color: AviaryColors.breeding,
            ),
            label: 'Breeding',
          ),
          NavigationDestination(
            icon: const AviaryIcon(AviaryIconType.finance),
            selectedIcon: const AviaryIcon(
              AviaryIconType.finance,
              filled: true,
              color: AviaryColors.finance,
            ),
            label: 'Finance',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: AviaryColors.history),
            label: 'Settings',
          ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}


class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin<_KeepAlivePage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
