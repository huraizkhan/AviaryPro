import 'package:flutter/material.dart';

import '../../ui/aviary_design.dart';
import '../backup/google_drive_backup_screen.dart';
import '../cages/cages_screen.dart';
import '../history/family_tree_screen.dart';
import '../history/history_screen.dart';
import 'ring_management_screen.dart';
import 'managed_bird_values_screen.dart';
import '../species/species_management_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  Widget _sectionTile({
    required BuildContext context,
    required Color color,
    required Widget icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: aviaryCardSurface(context, tint: color.withValues(alpha: .10)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: aviaryAvatarSurface(context),
            child: icon,
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      children: [
        _sectionTile(
          context: context,
          color: AviaryColors.cages,
          icon: const AviaryIcon(
            AviaryIconType.cage,
            color: AviaryColors.cages,
          ),
          title: 'Cages',
          subtitle: 'View and manage the original cage records',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CagesScreen()),
            );
          },
        ),
        _sectionTile(
          context: context,
          color: AviaryColors.breeding,
          icon: const AviaryIcon(
            AviaryIconType.bird,
            color: AviaryColors.breeding,
          ),
          title: 'Species Management',
          subtitle: 'Age stages, incubation and clutch rules',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SpeciesManagementScreen(),
              ),
            );
          },
        ),
        _sectionTile(
          context: context,
          color: AviaryColors.finance,
          icon: const Icon(
            Icons.cloud_sync_outlined,
            color: AviaryColors.finance,
          ),
          title: 'Backup & Sync',
          subtitle: 'Multi-device sync, scheduled backups and restore',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const GoogleDriveBackupScreen(),
              ),
            );
          },
        ),
        _sectionTile(
          context: context,
          color: AviaryColors.history,
          icon: const Icon(Icons.account_tree_outlined, color: AviaryColors.history),
          title: 'Family Tree',
          subtitle: 'Parents, mates and offspring pedigree',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FamilyTreeScreen()),
            );
          },
        ),
        _sectionTile(
          context: context,
          color: AviaryColors.history,
          icon: const Icon(Icons.history_outlined, color: AviaryColors.history),
          title: 'Bird History',
          subtitle: 'Births, sales, removals, pairs and first eggs by date',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            );
          },
        ),
        _sectionTile(
          context: context,
          color: AviaryColors.birds,
          icon: const Icon(Icons.tag_outlined, color: AviaryColors.birds),
          title: 'Ring Management',
          subtitle: 'Species ring ranges, assigned rings and available numbers',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RingManagementScreen()),
            );
          },
        ),
        _sectionTile(
          context: context,
          color: AviaryColors.breeding,
          icon: const Icon(Icons.auto_awesome_outlined, color: AviaryColors.breeding),
          title: 'Mutation Management',
          subtitle: 'Maintain allowed mutations for each species',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ManagedBirdValuesScreen(kind: 'Mutation'),
              ),
            );
          },
        ),
        _sectionTile(
          context: context,
          color: AviaryColors.birds,
          icon: const Icon(Icons.badge_outlined, color: AviaryColors.birds),
          title: 'Bird Name Management',
          subtitle: 'Maintain reusable bird names',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ManagedBirdValuesScreen(kind: 'Name'),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        const Card(
          child: ListTile(
            leading: AviaryIcon(AviaryIconType.bird),
            title: Text('Aviary Pro'),
            subtitle: Text('Local aviary records and breeding management'),
          ),
        ),
      ],
    );
  }
}
