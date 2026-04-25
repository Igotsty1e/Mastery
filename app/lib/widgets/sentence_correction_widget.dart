import 'package:flutter/material.dart';

class SentenceCorrectionWidget extends StatefulWidget {
  final String prompt;
  final bool enabled;
  final void Function(String corrected) onSubmit;

  const SentenceCorrectionWidget({
    super.key,
    required this.prompt,
    required this.onSubmit,
    this.enabled = true,
  });

  @override
  State<SentenceCorrectionWidget> createState() =>
      _SentenceCorrectionWidgetState();
}

class _SentenceCorrectionWidgetState extends State<SentenceCorrectionWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Pre-fill with the original sentence so the user edits in place.
    _controller = TextEditingController(text: widget.prompt);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final answer = _controller.text.trim();
    if (answer.isNotEmpty) widget.onSubmit(answer);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          enabled: widget.enabled,
          autofocus: true,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: widget.enabled ? _submit : null,
            child: const Text('Submit'),
          ),
        ),
      ],
    );
  }
}
