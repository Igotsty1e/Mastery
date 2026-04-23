import 'package:flutter/material.dart';
import '../models/lesson.dart';

class MultipleChoiceWidget extends StatefulWidget {
  final String prompt;
  final List<McOption> options;
  final bool enabled;
  final void Function(String optionId) onSubmit;

  const MultipleChoiceWidget({
    super.key,
    required this.prompt,
    required this.options,
    required this.onSubmit,
    this.enabled = true,
  });

  @override
  State<MultipleChoiceWidget> createState() => _MultipleChoiceWidgetState();
}

class _MultipleChoiceWidgetState extends State<MultipleChoiceWidget> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.prompt, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 20),
        Column(
          children: widget.options
              .map((opt) => RadioListTile<String>(
                    title: Text(opt.text),
                    value: opt.id,
                    groupValue: _selected,
                    onChanged: widget.enabled
                        ? (v) => setState(() => _selected = v)
                        : null,
                  ))
              .toList(),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: widget.enabled && _selected != null
                ? () => widget.onSubmit(_selected!)
                : null,
            child: const Text('Submit'),
          ),
        ),
      ],
    );
  }
}
