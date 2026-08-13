import 'package:flutter/painting.dart' show Color;

import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LedChannelFeedbackConfig / LedRowFeedbackConfig
//
// Presentation of the live LED indicator row — the layout's INPUT/OUTPUT
// FEEDBACK surface. Each LED renders two independent values that this config
// only styles, never produces: the ring is what the app COMMANDED, the core is
// what the PLC CONFIRMED (see live_led_row.dart). Nothing here can drive an
// output; the row is a mirror.
//
// Every per-channel field is nullable-for-default so a layout that has never
// been touched stores nothing and keeps picking up theme changes — the same
// contract ButtonStyleConfig uses. Defaults are resolved at render time by
// FeedbackManager.resolveLeds, not baked in here.
// ─────────────────────────────────────────────────────────────────────────────

class LedChannelFeedbackConfig {
  const LedChannelFeedbackConfig({
    this.label,
    this.activeColor,
    this.inactiveColor,
    this.pulseWhenInactive,
    this.blinkWhenPending = true,
    this.visible = true,
  });

  /// Operator-facing name; null uses the channel's own identity (`ESTOP` for
  /// DF1, otherwise the DF key).
  final String? label;

  /// Colour of a confirmed-ON core/ring. Null = theme default for the channel.
  final Color? activeColor;

  /// "Ready" colour shown while the channel is confirmed OFF — null leaves
  /// the LED dark when off, which is the normal industrial convention. Only
  /// safety-relevant channels (E-STOP) default to a lit ready state.
  final Color? inactiveColor;

  /// Whether the ready colour breathes. Null follows whether the channel has
  /// a ready colour by default (E-STOP does, others don't).
  final bool? pulseWhenInactive;

  /// Whether a commanded-but-not-yet-confirmed channel blinks amber. Turning
  /// this off makes the LED show confirmed state only — the ring stops
  /// annunciating disagreement, so it is deliberately opt-out, not opt-in.
  final bool blinkWhenPending;

  final bool visible;

  LedChannelFeedbackConfig copyWith({
    String? label,
    Color? activeColor,
    Color? inactiveColor,
    bool? pulseWhenInactive,
    bool? blinkWhenPending,
    bool? visible,
    bool clearLabel = false,
    bool clearActiveColor = false,
    bool clearInactiveColor = false,
    bool clearPulseWhenInactive = false,
  }) {
    return LedChannelFeedbackConfig(
      label: clearLabel ? null : (label ?? this.label),
      activeColor: clearActiveColor ? null : (activeColor ?? this.activeColor),
      inactiveColor: clearInactiveColor
          ? null
          : (inactiveColor ?? this.inactiveColor),
      pulseWhenInactive: clearPulseWhenInactive
          ? null
          : (pulseWhenInactive ?? this.pulseWhenInactive),
      blinkWhenPending: blinkWhenPending ?? this.blinkWhenPending,
      visible: visible ?? this.visible,
    );
  }

  /// True when nothing has been customized — used to keep the persisted map
  /// sparse rather than writing a full entry per channel.
  bool get isDefault =>
      label == null &&
      activeColor == null &&
      inactiveColor == null &&
      pulseWhenInactive == null &&
      blinkWhenPending &&
      visible;

  Map<String, dynamic> toJson() => {
    'label': label,
    'activeColor': activeColor?.toARGB32(),
    'inactiveColor': inactiveColor?.toARGB32(),
    'pulseWhenInactive': pulseWhenInactive,
    'blinkWhenPending': blinkWhenPending,
    'visible': visible,
  };

  factory LedChannelFeedbackConfig.fromJson(Map<String, dynamic> json) {
    final active = json['activeColor'] as num?;
    final inactive = json['inactiveColor'] as num?;
    return LedChannelFeedbackConfig(
      label: json['label'] as String?,
      activeColor: active != null ? Color(active.toInt()) : null,
      inactiveColor: inactive != null ? Color(inactive.toInt()) : null,
      pulseWhenInactive: json['pulseWhenInactive'] as bool?,
      blinkWhenPending: json['blinkWhenPending'] as bool? ?? true,
      visible: json['visible'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LedChannelFeedbackConfig &&
          other.label == label &&
          other.activeColor == activeColor &&
          other.inactiveColor == inactiveColor &&
          other.pulseWhenInactive == pulseWhenInactive &&
          other.blinkWhenPending == blinkWhenPending &&
          other.visible == visible;

  @override
  int get hashCode => Object.hash(
    label,
    activeColor,
    inactiveColor,
    pulseWhenInactive,
    blinkWhenPending,
    visible,
  );
}

class LedRowFeedbackConfig {
  const LedRowFeedbackConfig({
    this.channels = const <PlcOutputVariant, LedChannelFeedbackConfig>{},
    this.showUnmappedChannels = true,
    this.showPendingState = true,
  });

  /// Sparse per-channel overrides. An absent variant uses defaults entirely.
  final Map<PlcOutputVariant, LedChannelFeedbackConfig> channels;

  /// Whether channels no control in the layout can drive still appear (as the
  /// dashed grey "spare channel" ring). Hiding them shortens the row to the
  /// channels this layout actually uses.
  final bool showUnmappedChannels;

  /// Master switch for the commanded-vs-confirmed pending annunciation. Off
  /// makes every LED show confirmed PLC state only, for sites that treat the
  /// disagreement window as noise.
  final bool showPendingState;

  LedChannelFeedbackConfig channelFor(PlcOutputVariant variant) =>
      channels[variant] ?? const LedChannelFeedbackConfig();

  LedRowFeedbackConfig withChannel(
    PlcOutputVariant variant,
    LedChannelFeedbackConfig config,
  ) {
    final next = {...channels};
    // Keep the map sparse: a channel reset to defaults drops out entirely
    // rather than persisting a row of nulls.
    if (config.isDefault) {
      next.remove(variant);
    } else {
      next[variant] = config;
    }
    return copyWith(channels: next);
  }

  LedRowFeedbackConfig copyWith({
    Map<PlcOutputVariant, LedChannelFeedbackConfig>? channels,
    bool? showUnmappedChannels,
    bool? showPendingState,
  }) {
    return LedRowFeedbackConfig(
      channels: channels ?? this.channels,
      showUnmappedChannels: showUnmappedChannels ?? this.showUnmappedChannels,
      showPendingState: showPendingState ?? this.showPendingState,
    );
  }

  Map<String, dynamic> toJson() => {
    'channels': {
      for (final entry in channels.entries)
        entry.key.storageKey: entry.value.toJson(),
    },
    'showUnmappedChannels': showUnmappedChannels,
    'showPendingState': showPendingState,
  };

  factory LedRowFeedbackConfig.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'];
    final channels = <PlcOutputVariant, LedChannelFeedbackConfig>{};
    if (rawChannels is Map) {
      for (final entry in rawChannels.entries) {
        final variant = PlcOutputVariant.fromStorageKey(entry.key);
        final value = entry.value;
        if (variant == null || value is! Map) continue;
        channels[variant] = LedChannelFeedbackConfig.fromJson(
          value.cast<String, dynamic>(),
        );
      }
    }
    return LedRowFeedbackConfig(
      channels: channels,
      showUnmappedChannels: json['showUnmappedChannels'] as bool? ?? true,
      showPendingState: json['showPendingState'] as bool? ?? true,
    );
  }

  static bool _channelsEqual(
    Map<PlcOutputVariant, LedChannelFeedbackConfig> a,
    Map<PlcOutputVariant, LedChannelFeedbackConfig> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LedRowFeedbackConfig &&
          other.showUnmappedChannels == showUnmappedChannels &&
          other.showPendingState == showPendingState &&
          _channelsEqual(other.channels, channels);

  @override
  int get hashCode => Object.hash(
    showUnmappedChannels,
    showPendingState,
    Object.hashAllUnordered(
      channels.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
