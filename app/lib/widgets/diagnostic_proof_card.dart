// Wave 12.3 — diagnostic-mode welcome screen proof card.
//
// A tinted card on `bg.primary-soft` (rose-cream) with three short
// reassurance pairings: "5 questions", "~2 minutes", "Stays on your
// device". Used only on the diagnostic Welcome phase per
// `docs/plans/diagnostic-mode.md` Phase 1.

import 'package:flutter/material.dart';

import '../theme/mastery_theme.dart';

class DiagnosticProofCard extends StatelessWidget {
  const DiagnosticProofCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: MasterySpacing.lg,
        vertical: MasterySpacing.lg,
      ),
      decoration: BoxDecoration(
        color: MasteryColors.bgPrimarySoft,
        borderRadius: BorderRadius.circular(MasteryRadii.lg),
        border: Border.all(
          color: MasteryColors.actionPrimary.withAlpha(40),
          width: 1,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProofRow(
            icon: Icons.adjust,
            label: '5 questions',
          ),
          SizedBox(height: MasterySpacing.md),
          _ProofRow(
            icon: Icons.access_time,
            label: '~2 minutes',
          ),
          SizedBox(height: MasterySpacing.md),
          _ProofRow(
            icon: Icons.lock_outline,
            label: 'Stays on your device',
          ),
        ],
      ),
    );
  }
}

class _ProofRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ProofRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 20,
          color: MasteryColors.actionPrimaryPressed,
        ),
        const SizedBox(width: MasterySpacing.sm),
        Expanded(
          child: Text(
            label,
            style: MasteryTextStyles.bodyMd.copyWith(
              color: MasteryColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
