import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../database/database_helper.dart';
import '../../ui/aviary_design.dart';
import '../birds/bird_details_screen.dart';
import 'previous_birds_screen.dart';

class HistoryScreen extends StatefulWidget {
  final String? birdId;
  final String? birdLabel;

  const HistoryScreen({
    super.key,
    this.birdId,
    this.birdLabel,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _categories = ['All', 'Birds', 'Breeding'];
  final _dateFormat = DateFormat('dd-MMM-yy');
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _events = const [];
  String _selectedCategory = 'All';
  String _search = '';
  int _previousBirds = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait<dynamic>([
      DatabaseHelper.instance.getActivityEvents(
        category: widget.birdId == null ? _selectedCategory : null,
        birdId: widget.birdId,
      ),
      DatabaseHelper.instance.getPreviousBirdCount(),
    ]);
    if (!mounted) return;
    setState(() {
      _events = results[0] as List<Map<String, dynamic>>;
      _previousBirds = results[1] as int;
      _loading = false;
    });
  }

  String _dateKey(Map<String, dynamic> event) {
    final parsed = DateTime.tryParse(event['eventDate']?.toString() ?? '');
    if (parsed == null) return 'Unknown date';
    return _dateFormat.format(parsed);
  }

  String _normalizedType(Map<String, dynamic> event) {
    final type = event['eventType']?.toString() ?? 'Activity';
    if (const {'Sold', 'Bird Sold', 'Birds Sold'}.contains(type)) return 'Sold';
    if (const {'Purchased', 'Bird Purchased', 'Birds Purchased'}.contains(type)) {
      return 'Purchased';
    }
    return type;
  }

  String _groupKey(Map<String, dynamic> event) {
    final date = _dateKey(event);
    final type = _normalizedType(event);
    final entityId = event['entityId']?.toString() ?? '';
    final title = event['title']?.toString() ?? '';
    if (type == 'Chick Hatched') return '$date|$type|$entityId';
    if (type == 'First Egg Laid') return '$date|$type|$title';
    if (type.startsWith('Pair ')) return '$date|$type|$entityId';
    return '$date|$type';
  }

  List<_HistoryGroup> get _groups {
    final query = _search.trim().toLowerCase();
    final source = query.isEmpty
        ? _events
        : _events.where((event) {
            return [
              event['title'],
              event['eventType'],
              event['details'],
              event['category'],
            ].whereType<Object>().join(' ').toLowerCase().contains(query);
          }).toList();

    final grouped = <String, _HistoryGroup>{};
    for (final event in source) {
      final key = _groupKey(event);
      grouped.putIfAbsent(
        key,
        () => _HistoryGroup(
          dateLabel: _dateKey(event),
          type: _normalizedType(event),
          category: event['category']?.toString() ?? 'Birds',
          events: <Map<String, dynamic>>[],
        ),
      ).events.add(event);
    }
    return grouped.values.toList();
  }

  String _title(_HistoryGroup group) {
    final count = group.events.length;
    final first = group.events.first;
    final type = group.type;
    if (type == 'Chick Hatched') {
      return '$count chick${count == 1 ? '' : 's'} hatched';
    }
    if (type == 'Sold') {
      if (first['entityType']?.toString() == 'BirdSaleBatch') {
        return first['title']?.toString() ?? 'Birds sold';
      }
      return '$count bird${count == 1 ? '' : 's'} sold';
    }
    if (type == 'Purchased') {
      if (first['entityType']?.toString() == 'BirdPurchaseBatch') {
        return first['title']?.toString() ?? 'Birds purchased';
      }
      return '$count bird${count == 1 ? '' : 's'} purchased';
    }
    if (type == 'First Egg Laid') {
      return 'First egg laid · ${first['title'] ?? 'Pair'}';
    }
    return first['title']?.toString().trim().isNotEmpty == true
        ? first['title'].toString()
        : type;
  }

  String _details(_HistoryGroup group) {
    final values = <String>[];
    for (final event in group.events) {
      final title = event['title']?.toString().trim() ?? '';
      final details = event['details']?.toString().trim() ?? '';
      if (title.isNotEmpty && title != _title(group)) values.add(title);
      if (details.isNotEmpty && !details.toLowerCase().contains('price:')) {
        values.add(details);
      }
    }
    return values.toSet().take(4).join(' · ');
  }

  Widget _icon(_HistoryGroup group) {
    final type = group.type.toLowerCase();
    if (type.contains('egg')) return const AviaryIcon(AviaryIconType.egg, size: 21);
    if (type.contains('hatch')) return const AviaryIcon(AviaryIconType.chick, size: 21);
    if (type.contains('pair')) return const AviaryIcon(AviaryIconType.breeding, size: 21);
    if (type.contains('sold')) return const Icon(Icons.sell_outlined, size: 21);
    if (type.contains('died') || type.contains('removed')) {
      return const Icon(Icons.remove_circle_outline, size: 21);
    }
    return const AviaryIcon(AviaryIconType.bird, size: 21);
  }

  Future<void> _openEventBird(_HistoryGroup group) async {
    if (group.events.length != 1) return;
    final birdId = group.events.first['birdId']?.toString();
    if (birdId == null || birdId.isEmpty) return;
    final bird = await DatabaseHelper.instance.getBirdById(birdId);
    if (!mounted || bird == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BirdDetailsScreen(bird: bird)),
    );
    if (mounted) await _load();
  }

  Widget _eventCard(_HistoryGroup group) {
    final details = _details(group);
    final accent = group.category == 'Breeding' ? AviaryColors.breeding : AviaryColors.birds;
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: accent.withValues(alpha: .12),
          foregroundColor: accent,
          child: _icon(group),
        ),
        title: Text(
          _title(group),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: details.isEmpty
            ? null
            : Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: group.events.length == 1 &&
                (group.events.first['birdId']?.toString().isNotEmpty ?? false)
            ? const Icon(Icons.chevron_right)
            : null,
        onTap: group.events.length == 1 &&
                (group.events.first['birdId']?.toString().isNotEmpty ?? false)
            ? () => _openEventBird(group)
            : null,
      ),
    );
  }

  Widget _categoryBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: _categories.map((category) {
          final selected = category == _selectedCategory;
          return Padding(
            padding: const EdgeInsets.only(right: 7),
            child: ChoiceChip(
              label: Text(category),
              selected: selected,
              onSelected: (_) {
                if (selected) return;
                setState(() => _selectedCategory = category);
                _load();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.birdId == null ? 'Bird History' : '${widget.birdLabel ?? 'Bird'} History'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
                children: [
                  if (widget.birdId == null) ...[
                    Card(
                      color: AviaryColors.history.withValues(alpha: .10),
                      child: ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: const Text('Previous Birds', style: TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: const Text('Sold, died, gifted, flew away or otherwise removed'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_previousBirds',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PreviousBirdsScreen()),
                        ).then((_) => _load()),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _categoryBar(),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _search = value),
                    decoration: const InputDecoration(
                      hintText: 'Search bird history',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (groups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 100),
                      child: Center(child: Text('No bird history events yet.')),
                    )
                  else
                    ..._buildDatedGroups(groups),
                ],
              ),
            ),
    );
  }

  List<Widget> _buildDatedGroups(List<_HistoryGroup> groups) {
    final widgets = <Widget>[];
    String? lastDate;
    for (final group in groups) {
      if (group.dateLabel != lastDate) {
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 8));
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 5, 4, 7),
            child: Text(
              group.dateLabel,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
        );
        lastDate = group.dateLabel;
      }
      widgets.add(_eventCard(group));
    }
    return widgets;
  }
}

class _HistoryGroup {
  final String dateLabel;
  final String type;
  final String category;
  final List<Map<String, dynamic>> events;

  _HistoryGroup({
    required this.dateLabel,
    required this.type,
    required this.category,
    required this.events,
  });
}
