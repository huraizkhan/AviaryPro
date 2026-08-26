import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

Future<DateTime?> showAviaryDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final minDate = firstDate ?? DateTime(2000, 1, 1);
  final maxDate = lastDate ?? DateTime.now();
  var selected = _clampDate(initialDate, minDate, maxDate);

  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        void update({int? day, int? month, int? year}) {
          final targetYear = year ?? selected.year;
          final targetMonth = month ?? selected.month;
          final maxDay = DateTime(targetYear, targetMonth + 1, 0).day;
          final targetDay = (day ?? selected.day).clamp(1, maxDay).toInt();
          final next = _clampDate(
            DateTime(targetYear, targetMonth, targetDay),
            minDate,
            maxDate,
          );
          setSheetState(() => selected = next);
        }

        final years = <int>[
          for (var year = minDate.year; year <= maxDate.year; year++) year,
        ];
        final months = <int>[for (var month = 1; month <= 12; month++) month];
        final maxDay = DateTime(selected.year, selected.month + 1, 0).day;
        final days = <int>[for (var day = 1; day <= maxDay; day++) day];

        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select Date',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    DateFormat('dd-MMM-yy').format(selected),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DateNumberInput(
                      label: 'Day',
                      value: selected.day,
                      min: 1,
                      max: maxDay,
                      onChanged: (value) => update(day: value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DateNumberInput(
                      label: 'Month',
                      value: selected.month,
                      min: 1,
                      max: 12,
                      onChanged: (value) => update(month: value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DateNumberInput(
                      label: 'Year',
                      value: selected.year,
                      min: minDate.year,
                      max: maxDate.year,
                      onChanged: (value) => update(year: value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 154,
                child: Row(
                  children: [
                    Expanded(
                      child: _Wheel<int>(
                        values: days,
                        value: selected.day,
                        labelFor: (value) => value.toString().padLeft(2, '0'),
                        onChanged: (value) => update(day: value),
                      ),
                    ),
                    Expanded(
                      child: _Wheel<int>(
                        values: months,
                        value: selected.month,
                        labelFor: (value) => DateFormat('MMM').format(DateTime(2024, value)),
                        onChanged: (value) => update(month: value),
                      ),
                    ),
                    Expanded(
                      child: _Wheel<int>(
                        values: years,
                        value: selected.year,
                        labelFor: (value) => '$value',
                        onChanged: (value) => update(year: value),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext, selected),
                      child: const Text('Use Date'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

DateTime _clampDate(DateTime value, DateTime min, DateTime max) {
  final date = DateTime(value.year, value.month, value.day);
  final lower = DateTime(min.year, min.month, min.day);
  final upper = DateTime(max.year, max.month, max.day);
  if (date.isBefore(lower)) return lower;
  if (date.isAfter(upper)) return upper;
  return date;
}

class _DateNumberInput extends StatefulWidget {
  const _DateNumberInput({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_DateNumberInput> createState() => _DateNumberInputState();
}

class _DateNumberInputState extends State<_DateNumberInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode()..addListener(_commitWhenDone);
  }

  @override
  void didUpdateWidget(covariant _DateNumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && oldWidget.value != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  void _commitWhenDone() {
    if (_focusNode.hasFocus) return;
    _commit();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    final value = (parsed ?? widget.value).clamp(widget.min, widget.max).toInt();
    _controller.text = '$value';
    widget.onChanged(value);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_commitWhenDone)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      onSubmitted: (_) => _commit(),
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _Wheel<T> extends StatelessWidget {
  const _Wheel({
    required this.values,
    required this.value,
    required this.labelFor,
    required this.onChanged,
  });

  final List<T> values;
  final T value;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    var initialIndex = values.indexOf(value);
    if (initialIndex < 0) initialIndex = 0;
    return CupertinoPicker(
      scrollController: FixedExtentScrollController(initialItem: initialIndex),
      itemExtent: 38,
      magnification: 1.08,
      useMagnifier: true,
      onSelectedItemChanged: (index) => onChanged(values[index]),
      children: values
          .map(
            (item) => Center(
              child: Text(
                labelFor(item),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          )
          .toList(),
    );
  }
}
