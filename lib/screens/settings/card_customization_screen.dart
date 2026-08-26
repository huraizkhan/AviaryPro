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
    'species': 'Species',
    'mutation': 'Mutation / color',
    'age': 'Age group',
    'cage': 'Cage',
    'pair': 'Paired status',
    'eyeColor': 'Eye color',
  };

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
                  const Text(
                    'Arrange cards like tiles',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Drag cards to reorder them, hide cards you do not need, and reset any screen at any time.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: screen,
                    decoration: const InputDecoration(labelText: 'Screen'),
                    items: screenLabels.entries
                        .map((entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ))
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
                    onReorderItem: (oldIndex, newIndex) =>
                        prefs.reorder(screen, oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final id = order[index];
                      final visible = prefs.isVisible(screen, id);
                      return ListTile(
                        key: ValueKey('$screen-$id'),
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
                        title: Text(cardLabels[id] ?? id),
                        trailing: Switch(
                          value: visible,
                          onChanged: (value) =>
                              prefs.setVisible(screen, id, value),
                        ),
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
            Text(
              'Bird card data',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ...birdFieldLabels.entries.map(
                    (entry) => SwitchListTile(
                      title: Text(entry.value),
                      value: prefs.birdFieldVisible(entry.key),
                      onChanged: (value) =>
                          prefs.setBirdFieldVisible(entry.key, value),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: prefs.resetBirdFields,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reset bird fields'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.science_outlined),
              title: Text('Experimental'),
              subtitle: Text(
                'This first version customizes the main summary/card areas and bird-card data. More card types can use the same system later.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
