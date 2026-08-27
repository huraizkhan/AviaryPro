import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../../ui/aviary_design.dart';
import '../backup/google_drive_backup_screen.dart';
import 'card_customization_screen.dart';
import '../cages/cages_screen.dart';
import '../history/family_tree_screen.dart';
import '../history/history_screen.dart';
import '../more/managed_bird_values_screen.dart';
import '../more/ring_management_screen.dart';
import '../species/species_management_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<ThemeProvider>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      children: [
        Text(
          'Appearance',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Mode', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {appearance.mode},
                  onSelectionChanged: (value) => appearance.setMode(value.first),
                ),
                const SizedBox(height: 16),
                const Text('Theme', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AviaryThemePreset.values.map((preset) {
                    final selected = appearance.preset == preset;
                    final label = switch (preset) {
                      AviaryThemePreset.classic => 'Classic Aviary Pro',
                      AviaryThemePreset.olive => 'Olive',
                      AviaryThemePreset.ocean => 'Ocean',
                      AviaryThemePreset.plum => 'Plum',
                    };
                    return ChoiceChip(
                      selected: selected,
                      label: Text(label),
                      onSelected: (_) => appearance.setPreset(preset),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.dashboard_customize_outlined,
          title: 'Experimental Layout',
          subtitle: 'Reorder/hide summary cards and choose bird-card data',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CardCustomizationScreen(),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Data & Sync',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.cloud_sync_outlined,
          title: 'Backup & Sync',
          subtitle: 'Google Drive connection, sync, backups and restore',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GoogleDriveBackupScreen()),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Aviary Management',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.grid_view_outlined,
          title: 'Cages',
          subtitle: 'Manage cage records and locations',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CagesScreen()),
          ),
        ),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.pets_outlined,
          title: 'Species',
          subtitle: 'Age stages, incubation and clutch rules',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SpeciesManagementScreen()),
          ),
        ),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.tag_outlined,
          title: 'Rings',
          subtitle: 'Ranges, allotted rings and available numbers',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RingManagementScreen()),
          ),
        ),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.auto_awesome_outlined,
          title: 'Mutations',
          subtitle: 'Reusable species-aware mutation values',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ManagedBirdValuesScreen(kind: 'Mutation'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.badge_outlined,
          title: 'Bird Names',
          subtitle: 'Reusable bird names',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ManagedBirdValuesScreen(kind: 'Name'),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Records',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.account_tree_outlined,
          title: 'Family Tree',
          subtitle: 'Parents, mates and offspring pedigree',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FamilyTreeScreen()),
          ),
        ),
        const SizedBox(height: 8),
        _tile(
          icon: Icons.history_outlined,
          title: 'Bird History',
          subtitle: 'Important lifecycle and breeding events',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HistoryScreen()),
          ),
        ),
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: AviaryIcon(AviaryIconType.bird),
            title: Text('Aviary Pro'),
            subtitle: Text('v1.4.19+28 · Pair lists and grid views'),
          ),
        ),
      ],
    );
  }
}
