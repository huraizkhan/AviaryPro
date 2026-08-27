import 'package:flutter/material.dart';

class AviaryListGridToggle extends StatelessWidget {
  const AviaryListGridToggle({
    super.key,
    required this.gridView,
    required this.onChanged,
  });

  final bool gridView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment<bool>(
          value: false,
          icon: Icon(Icons.view_list_outlined),
          label: Text('List'),
        ),
        ButtonSegment<bool>(
          value: true,
          icon: Icon(Icons.grid_view_outlined),
          label: Text('Grid'),
        ),
      ],
      selected: {gridView},
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
