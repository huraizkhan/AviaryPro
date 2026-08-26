import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/card_customization_provider.dart';

class CardCustomizationScreen extends StatefulWidget {
  const CardCustomizationScreen({super.key});

  @override
  State<CardCustomizationScreen> createState() => _CardCustomizationScreenState();
}

class _CardCustomizationScreenState extends State<CardCustomizationScreen> {
  String screen = 'dashboard';

  static const screenLabels = {
    'dashboard': 'Dashboard',
    'birds': 'Birds',
    'breeding': 'Breeding',
    'finance': 'Finance',
  };

  static const cardLabels = {
    'birds': 'Current Birds',
    'eggs': 'Eggs',
    'pairs': 'Active Pairs',
    'chicks': 'Chicks',
    'summary': 'Birds Summary',
    'automaticCount': 'Automatic Count',
    'allPairs': 'All Pairs',
    'activePairs': 'Active Breeding Pairs',
    'month': 'This Month',
    'year': 'This Year',
    'feed': 'Feed Trend',
  };

  static const birdFieldLabels = {
    'cage': 'Cage',
    'species': 'Species',
    'mutation': 'Mutation / color',
    'age': 'Age group',
    'pair': 'Pair status',
    'saleStatus': 'Sale status',
    'gender': 'Gender',
    'eyeColor': 'Eye color',
    'downColor': 'Down / chick color',
    'mate': 'Mate',
    'parents': 'Parents',
    'parentCages': 'Parent cage(s)',
    'source': 'Source',
    'hatchDate': 'Hatch date',
    'sourceDate': 'Purchase / source date',
    'nest': 'Nest status',
    'notes': 'Notes indicator',
  };

  static const styleLabels = {
    'pill': 'Pill',
    'text': 'Text',
    'icon': 'Icon',
    'hidden': 'Hidden',
  };

  IconData _fieldIcon(String id) => switch (id) {
        'cage' => Icons.home_work_outlined,
        'species' => Icons.pets_outlined,
        'mutation' => Icons.palette_outlined,
        'age' => Icons.cake_outlined,
        'pair' => Icons.favorite_outline,
        'saleStatus' => Icons.sell_outlined,
        'gender' => Icons.wc_outlined,
        'eyeColor' => Icons.visibility_outlined,
        'downColor' => Icons.brush_outlined,
        'mate' => Icons.favorite_border,
        'parents' => Icons.account_tree_outlined,
        'parentCages' => Icons.home_outlined,
        'source' => Icons.info_outline,
        'hatchDate' => Icons.egg_outlined,
        'sourceDate' => Icons.event_outlined,
        'nest' => Icons.home_outlined,
        'notes' => Icons.notes_outlined,
        _ => Icons.label_outline,
      };

  String _previewValue(String id) => switch (id) {
        'cage' => 'Cage3',
        'species' => 'Cockatiel',
        'mutation' => 'Cream',
        'age' => 'Adult',
        'pair' => 'Paired',
        'saleStatus' => 'For Sale',
        'gender' => 'Male',
        'eyeColor' => 'Black eyes',
        'downColor' => 'Yellow down',
        'mate' => 'Mate 037',
        'parents' => '05 × 03',
        'parentCages' => 'Parents Cage9',
        'source' => 'Bred',
        'hatchDate' => '02-Nov-24',
        'sourceDate' => '18-Aug-26',
        'nest' => 'In nest',
        'notes' => 'Notes',
        _ => id,
      };

  Widget _previewField(BuildContext context, String id, String style) {
    final value = _previewValue(id);
    if (style == 'text') {
      return Padding(
        padding: const EdgeInsets.only(right: 10, bottom: 5),
        child: Text(value, style: Theme.of(context).textTheme.bodySmall),
      );
    }
    if (style == 'icon') {
      return Padding(
        padding: const EdgeInsets.only(right: 7, bottom: 5),
        child: Tooltip(message: value, child: Icon(_fieldIcon(id), size: 19)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 5, bottom: 5),
      child: Chip(
        avatar: Icon(_fieldIcon(id), size: 15),
        label: Text(value),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _birdCardEditor(CardCustomizationProvider prefs) {
    final visible = prefs.birdFieldOrder
        .where((id) => prefs.birdFieldStyle(id) != 'hidden')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bird Card Layout',
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
                const Text('Live preview', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.pets_outlined)),
                    title: Text(
                      '038 — Cream',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        children: visible
                            .map((id) => _previewField(context, id, prefs.birdFieldStyle(id)))
                            .toList(),
                      ),
                    ),
                    trailing: const Icon(Icons.more_vert),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Drag fields into the order you recognize fastest. Each field can be a pill, small text, icon only, or hidden.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Column(
              children: [
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: prefs.birdFieldOrder.length,
                  onReorderItem: prefs.reorderBirdField,
                  itemBuilder: (context, index) {
                    final id = prefs.birdFieldOrder[index];
                    final style = prefs.birdFieldStyle(id);
                    return ListTile(
                      key: ValueKey('bird-field-$id'),
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle),
                      ),
                      title: Text(birdFieldLabels[id] ?? id),
                      subtitle: Text(styleLabels[style] ?? style),
                      trailing: DropdownButton<String>(
                        value: style,
                        underline: const SizedBox.shrink(),
                        items: styleLabels.entries
                            .map((entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) prefs.setBirdFieldStyle(id, value);
                        },
                      ),
                    );
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: prefs.resetBirdFields,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset Bird Card'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<CardCustomizationProvider>();
    final order = prefs.orderFor(screen);
    return Scaffold(
      appBar: AppBar(title: const Text('Experimental Layout')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Arrange cards like tiles', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  const Text('Drag cards to reorder them, hide cards you do not need, and reset any screen at any time.'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: screen,
                    decoration: const InputDecoration(labelText: 'Screen'),
                    items: screenLabels.entries
                        .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => screen = value);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Column(
                children: [
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: order.length,
                    onReorderItem: (oldIndex, newIndex) => prefs.reorder(screen, oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final id = order[index];
                      final visible = prefs.isVisible(screen, id);
                      return ListTile(
                        key: ValueKey('$screen-$id'),
                        leading: ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle)),
                        title: Text(cardLabels[id] ?? id),
                        trailing: Switch(value: visible, onChanged: (value) => prefs.setVisible(screen, id, value)),
                      );
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => prefs.resetScreen(screen),
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reset screen'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (screen == 'birds') ...[
            const SizedBox(height: 14),
            _birdCardEditor(prefs),
          ],
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.science_outlined),
              title: Text('Experimental'),
              subtitle: Text('Layout preferences are visual only and can always be reset to defaults.'),
            ),
          ),
        ],
      ),
    );
  }
}
