import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync_provider.dart';

class SyncIconButton extends ConsumerStatefulWidget {
  const SyncIconButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Synchroniser',
  });

  final Future<void> Function() onPressed;
  final String tooltip;

  @override
  ConsumerState<SyncIconButton> createState() => _SyncIconButtonState();
}

class _SyncIconButtonState extends ConsumerState<SyncIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  void _updateAnimation(bool syncing) {
    if (syncing) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else if (_rotation.isAnimating || _rotation.value != 0) {
      _rotation
        ..stop()
        ..value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncing = ref.watch(syncInProgressProvider);
    ref.listen<bool>(syncInProgressProvider, (_, next) {
      _updateAnimation(next);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateAnimation(syncing);
    });

    return IconButton(
      tooltip: syncing ? 'Synchronisation en cours' : widget.tooltip,
      onPressed: syncing ? null : widget.onPressed,
      icon: RotationTransition(turns: _rotation, child: const Icon(Icons.sync)),
    );
  }
}
