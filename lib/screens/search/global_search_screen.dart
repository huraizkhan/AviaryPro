import 'dart:async';

import 'package:flutter/material.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../birds/bird_details_screen.dart';
import '../breeding/clutch_details_screen.dart';
import '../breeding/pair_details_screen.dart';
import '../cages/cage_details_screen.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final controller = TextEditingController();
  Timer? debounce;
  List<Map<String, dynamic>> results = [];
  bool loading = false;

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) setState(() => results = []);
      return;
    }
    if (mounted) setState(() => loading = true);
    final rows = await DatabaseHelper.instance.globalSearch(query);
    if (!mounted) return;
    setState(() {
      results = rows;
      loading = false;
    });
  }

  Widget _icon(String type) {
    return switch (type) {
      'Bird' => const AviaryIcon(AviaryIconType.bird),
      'Cage' => const AviaryIcon(AviaryIconType.cage),
      'Pair' => const AviaryIcon(AviaryIconType.pair),
      'Clutch' => const AviaryIcon(AviaryIconType.breeding),
      'Egg' => const AviaryIcon(AviaryIconType.egg),
      _ => const Icon(Icons.search),
    };
  }

  Color _tint(String type) {
    return switch (type) {
      'Bird' => AviaryColors.birds.withValues(alpha: .10),
      'Cage' => AviaryColors.cages.withValues(alpha: .10),
      'Pair' => AviaryColors.paired,
      'Clutch' => AviaryColors.eggsNormal,
      'Egg' => AviaryColors.eggsNormal,
      _ => Colors.transparent,
    };
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final type = item['type']?.toString();
    final id = item['id']?.toString();
    if (id == null) return;

    Widget? screen;
    if (type == 'Bird') {
      final bird = await DatabaseHelper.instance.getBirdById(id);
      if (!mounted || bird == null) return;
      screen = BirdDetailsScreen(bird: bird);
    } else if (type == 'Cage') {
      final cage = await DatabaseHelper.instance.getCageById(id);
      if (!mounted || cage == null) return;
      screen = CageDetailsScreen(cageId: cage['id'].toString());
    } else if (type == 'Pair') {
      screen = PairDetailsScreen(pairId: id);
    } else if (type == 'Clutch') {
      screen = ClutchDetailsScreen(clutchId: id);
    } else if (type == 'Egg') {
      screen = ClutchDetailsScreen(
        clutchId: item['targetId']?.toString() ?? id,
      );
    }

    if (!mounted || screen == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen!),
    );
    if (!mounted) return;
    await _search(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _search,
          decoration: const InputDecoration(
            hintText: 'Search birds, cages, pairs, notes...',
            border: InputBorder.none,
          ),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : controller.text.trim().isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Search by bird name or ring, cage, pair, species, mutation, egg status, or any saved note.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : results.isEmpty
                  ? const Center(child: Text('No matching record'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final item = results[index];
                        final notes = item['notes']?.toString().trim() ?? '';
                        return Card(
                          color: aviaryCardSurface(
                            context,
                            tint: _tint(item['type']?.toString() ?? ''),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: aviaryAvatarSurface(context),
                              child: _icon(item['type']?.toString() ?? ''),
                            ),
                            title: Text(
                              item['title']?.toString() ?? 'Result',
                              style: TextStyle(
                                color: item['type'] == 'Bird'
                                    ? birdGenderTextColor(
                                        item['gender']?.toString(),
                                      )
                                    : null,
                                fontWeight: item['type'] == 'Bird'
                                    ? FontWeight.w700
                                    : null,
                              ),
                            ),
                            subtitle: item['type'] == 'Pair'
                                ? Text.rich(
                                    TextSpan(
                                      children: [
                                        const TextSpan(text: 'Pair · '),
                                        TextSpan(
                                          text: item['maleRingNumber']
                                                  ?.toString() ??
                                              'Male',
                                          style: TextStyle(
                                            color: birdGenderTextColor(
                                              item['maleGender']?.toString(),
                                            ),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const TextSpan(text: ' × '),
                                        TextSpan(
                                          text: item['femaleRingNumber']
                                                  ?.toString() ??
                                              'Female',
                                          style: TextStyle(
                                            color: birdGenderTextColor(
                                              item['femaleGender']?.toString(),
                                            ),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (notes.isNotEmpty)
                                          TextSpan(text: '\nNote: $notes'),
                                      ],
                                    ),
                                  )
                                : Text(
                                    '${item['type']} · ${item['subtitle'] ?? ''}'
                                    '${notes.isEmpty ? '' : '\nNote: $notes'}',
                                  ),
                            isThreeLine: notes.isNotEmpty,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open(item),
                          ),
                        );
                      },
                    ),
    );
  }
}
