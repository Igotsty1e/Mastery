// MasteryAudioPlayer — single-clip, replay-only, transcript-on-demand audio
// control used by `listening_discrimination` exercises. Visual contract per
// DESIGN.md §14 Audio Player.
//
// Notes:
// - We instantiate `AudioPlayer` per widget so each instance has its own
//   playback state. The widget disposes the player on unmount.
// - `audioplayers` throws `MissingPluginException` in pure Dart unit tests.
//   The widget is built so that all play/dispose calls are guarded behind a
//   try/catch — listening exercise tests can construct the widget without
//   needing a fake plugin registry, and the existing widget_test.dart suite
//   stays green even though it never exercises a listening item.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../theme/mastery_theme.dart';

class MasteryAudioPlayer extends StatefulWidget {
  /// Fully-resolved playback URL (already prefixed with the API base host).
  final String url;

  /// Plain text rendered when the learner taps `Show transcript`.
  final String transcript;

  /// Whether the audio control is enabled. Disabled after submit so the
  /// learner can still replay but not change focus state.
  final bool enabled;

  const MasteryAudioPlayer({
    super.key,
    required this.url,
    required this.transcript,
    this.enabled = true,
  });

  @override
  State<MasteryAudioPlayer> createState() => _MasteryAudioPlayerState();
}

enum _PlayState { idle, playing, finished, failed }

class _MasteryAudioPlayerState extends State<MasteryAudioPlayer>
    with SingleTickerProviderStateMixin {
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;
  late final AnimationController _pulse;

  _PlayState _state = _PlayState.idle;
  bool _showTranscript = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _pulse = AnimationController(
      vsync: this,
      duration: MasteryDurations.long,
    );
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      switch (s) {
        case PlayerState.playing:
          setState(() => _state = _PlayState.playing);
          _pulse.repeat(reverse: true);
          break;
        case PlayerState.completed:
        case PlayerState.stopped:
          setState(() => _state = _PlayState.finished);
          _pulse.stop();
          _pulse.value = 0;
          break;
        case PlayerState.paused:
        case PlayerState.disposed:
          break;
      }
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _state = _PlayState.finished);
      _pulse.stop();
      _pulse.value = 0;
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _completeSub?.cancel();
    _pulse.dispose();
    try {
      _player.dispose();
    } catch (_) {
      // ignore platform errors during teardown
    }
    super.dispose();
  }

  Future<void> _play() async {
    if (!widget.enabled) return;
    try {
      await _player.stop();
      await _player.play(UrlSource(widget.url));
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _PlayState.failed);
      _pulse.stop();
    }
  }

  void _toggleTranscript() {
    if (!widget.enabled && _showTranscript) return;
    setState(() => _showTranscript = !_showTranscript);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final isPlaying = _state == _PlayState.playing;
    final hasPlayed = _state != _PlayState.idle;
    final failed = _state == _PlayState.failed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isPlaying)
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (_, __) {
                      final t = _pulse.value;
                      return Container(
                        width: 64 + 8 * t,
                        height: 64 + 8 * t,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tokens.bgPrimarySoft.withAlpha(
                            (0.30 * 255).round(),
                          ),
                        ),
                      );
                    },
                  ),
                _PlayButton(
                  enabled: widget.enabled && !failed,
                  hasPlayed: hasPlayed,
                  failed: failed,
                  onTap: _play,
                ),
              ],
            ),
          ),
        ),
        if (failed) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Audio unavailable. Try again.',
              style: MasteryTextStyles.labelSm.copyWith(
                color: tokens.textTertiary,
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _toggleTranscript,
              style: TextButton.styleFrom(
                foregroundColor: MasteryColors.textSecondary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _showTranscript ? 'Hide transcript' : 'Show transcript',
                style: MasteryTextStyles.labelMd.copyWith(
                  color: MasteryColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
        if (_showTranscript)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AnimatedSlide(
              duration: MasteryDurations.short,
              curve: MasteryEasing.enter,
              offset: Offset.zero,
              child: AnimatedOpacity(
                duration: MasteryDurations.short,
                opacity: 1,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(MasterySpacing.md),
                  decoration: BoxDecoration(
                    color: tokens.bgPrimarySoft,
                    border: Border.all(
                      color: MasteryColors.actionPrimary.withAlpha(56),
                    ),
                    borderRadius: BorderRadius.circular(MasteryRadii.md),
                  ),
                  child: Text(
                    widget.transcript,
                    style: MasteryTextStyles.bodyMd.copyWith(
                      color: MasteryColors.textPrimary,
                      height: 1.55,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool enabled;
  final bool hasPlayed;
  final bool failed;
  final VoidCallback onTap;

  const _PlayButton({
    required this.enabled,
    required this.hasPlayed,
    required this.failed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final bg = failed ? tokens.borderStrong : MasteryColors.actionPrimary;
    final fg = MasteryColors.bgSurface;

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            boxShadow: enabled ? tokens.shadowButton : const [],
          ),
          alignment: Alignment.center,
          child: Icon(
            failed
                ? Icons.volume_off_outlined
                : hasPlayed
                    ? Icons.replay_rounded
                    : Icons.play_arrow_rounded,
            size: 32,
            color: fg,
          ),
        ),
      ),
    );
  }
}
