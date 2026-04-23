import 'package:flutter/material.dart';

class FillBlankWidget extends StatefulWidget {
  final String prompt;
  final String? hint;
  final bool enabled;
  final void Function(String answer) onSubmit;

  const FillBlankWidget({
    super.key,
    required this.prompt,
    required this.onSubmit,
    this.hint,
    this.enabled = true,
  });

  @override
  State<FillBlankWidget> createState() => _FillBlankWidgetState();
}

class _FillBlankWidgetState extends State<FillBlankWidget> {
  final _controller = TextEditingController();

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
        Text(widget.prompt, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          enabled: widget.enabled,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Type your answer',
          ),
        ),
        if (widget.hint != null) ...[
          const SizedBox(height: 8),
          Text(
            'Hint: ${widget.hint}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey[600]),
          ),
        ],
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
