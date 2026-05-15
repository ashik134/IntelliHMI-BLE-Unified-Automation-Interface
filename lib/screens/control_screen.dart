import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import 'package:rev6_crane_control_ops/utils/constants.dart';
import 'package:rev6_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev6_crane_control_ops/widgets/estop_swipe_button.dart';

// ═══════════════════════════════════════════════════════════════
// ControlScreen — Deadman Hold-to-Run Industrial Controls
//
// Behavior:
//   • UP button pressed  → Output ON [0,1,0]
//   • UP button released → Output OFF [0,0,0]
//   • DOWN button pressed  → Output ON [0,0,1]
//   • DOWN button released → Output OFF [0,0,0]
//
// Safety Rules:
//   • Only ONE direction active at any time
//   • UP active → DOWN disabled
//   • DOWN active → UP disabled
//   • Mutual exclusion enforced in hardware AND software
//   • Both buttons released → IDLE
// ═══════════════════════════════════════════════════════════════

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with SingleTickerProviderStateMixin {
  
  late final AnimationController _pulseController;
  CraneController? _craneController;

  // ── Deadman state tracking ──────────────────────────────
  bool _upPressed = false;
  bool _downPressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<CraneController>();
      _craneController = controller;
      controller.addListener(_onControllerChange);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _craneController?.removeListener(_onControllerChange);
    super.dispose();
  }

  void _onControllerChange() {
    final controller = _craneController;
    if (!mounted || controller == null) return;

    if (controller.isDisconnected) {
      // Auto-release both buttons on disconnect
      setState(() {
        _upPressed = false;
        _downPressed = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.errorMessage ?? 'Disconnected from PLC14'),
          backgroundColor: AppColors.eStopColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Deadman Hold-to-Run Handlers
  // ═══════════════════════════════════════════════════════════

  /// UP button pressed — activate UP output, disable DOWN
  void _onUpPressed() {
    final controller = _craneController;
    if (controller == null) return;
    if (controller.estopLatched || !controller.isConnected) return;
    if (_downPressed) return; // Mutual exclusion: DOWN is active
    
    setState(() => _upPressed = true);
    HapticFeedback.mediumImpact();
    Vibration.vibrate(duration: 30, amplitude: 128);
    
    // Send command: [estop=0, up=1, down=0, fast=0]
    controller.sendCommand(estop: false, up: true, down: false, fast: false);
  }

  /// UP button released — deactivate UP output
  void _onUpReleased() {
    final controller = _craneController;
    if (controller == null) return;
    
    setState(() => _upPressed = false);
    
    // Send command: [estop=0, up=0, down=0, fast=0]
    controller.sendCommand(estop: false, up: false, down: false, fast: false);
  }

  /// DOWN button pressed — activate DOWN output, disable UP
  void _onDownPressed() {
    final controller = _craneController;
    if (controller == null) return;
    if (controller.estopLatched || !controller.isConnected) return;
    if (_upPressed) return; // Mutual exclusion: UP is active
    
    setState(() => _downPressed = true);
    HapticFeedback.mediumImpact();
    Vibration.vibrate(duration: 30, amplitude: 128);
    
    // Send command: [estop=0, up=0, down=1, fast=0]
    controller.sendCommand(estop: false, up: false, down: true, fast: false);
  }

  /// DOWN button released — deactivate DOWN output
  void _onDownReleased() {
    final controller = _craneController;
    if (controller == null) return;
    
    setState(() => _downPressed = false);
    
    // Send command: [estop=0, up=0, down=0, fast=0]
    controller.sendCommand(estop: false, up: false, down: false, fast: false);
  }

  // ═══════════════════════════════════════════════════════════
  // E-Stop Handlers
  // ═══════════════════════════════════════════════════════════

  Future<void> _onEStopTap() async {
    final controller = context.read<CraneController>();
    
    // Release both deadman buttons
    setState(() {
      _upPressed = false;
      _downPressed = false;
    });
    
    await controller.triggerEStop();
    Vibration.vibrate(duration: 600, amplitude: 255);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'EMERGENCY STOP ACTIVATED',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: AppColors.eStopColor,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _onResetEStopTap() async {
    final controller = _craneController;
    if (controller == null) return;
    if (controller.currentScreen != AppScreen.control || !controller.isConnected) {
      return;
    }
    await controller.resetEStop();
    Vibration.vibrate(duration: 100);
  }

  // ═══════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Consumer<CraneController>(
      builder: (ctx, controller, _) {
        final isDisabled = controller.estopLatched || !controller.isConnected;
        
        return Scaffold(
          backgroundColor: ConnectionColors.background,
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            backgroundColor: ConnectionColors.surface,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.connectedDeviceName ?? BLEConstants.deviceName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: ConnectionColors.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: controller.isConnected
                            ? AppColors.upColorLight
                            : AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(
                      controller.isConnected ? 'Connected' : 'Disconnected',
                      style: TextStyle(
                        color: controller.isConnected
                            ? AppColors.upColorLight
                            : AppColors.danger,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.bluetooth_disabled,
                  size: 20,
                  color: ConnectionColors.textSecondary,
                ),
                tooltip: 'Disconnect',
                onPressed: () {
                  setState(() {
                    _upPressed = false;
                    _downPressed = false;
                  });
                  controller.disconnect();
                },
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: ConnectionColors.divider),
            ),
          ),
          body: SafeArea(
            maintainBottomViewPadding: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                children: [
                  // ── E-Stop / Reset Section ──────────────
                  controller.estopLatched
                      ? _buildResetSection()
                      : _buildEStopButton(),
                  
                  const SizedBox(height: 8),
                  
                  // ── Live LED Indicators ──────────────────
                  _liveLEDs(controller),
                  
                  const SizedBox(height: 8),
                  
                  // ── Deadman Hold-to-Run Buttons ──────────
                  Expanded(
                    child: Row(
                      children: [
                        // UP Button
                        Expanded(
                          child: _DeadmanButton(
                            label: 'HOIST\nUP',
                            icon: Icons.arrow_upward_rounded,
                            color: AppColors.upColor,
                            colorLight: AppColors.upColorLight,
                            isPressed: _upPressed,
                            isDisabled: isDisabled || _downPressed,
                            onPressed: _onUpPressed,
                            onReleased: _onUpReleased,
                          ),
                        ),
                        
                        const SizedBox(width: 16),
                        
                        // DOWN Button
                        Expanded(
                          child: _DeadmanButton(
                            label: 'HOIST\nDOWN',
                            icon: Icons.arrow_downward_rounded,
                            color: AppColors.downColor,
                            colorLight: AppColors.downColorLight,
                            isPressed: _downPressed,
                            isDisabled: isDisabled || _upPressed,
                            onPressed: _onDownPressed,
                            onReleased: _onDownReleased,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // ── Status Bar ───────────────────────────
                  _buildStatusBar(controller),
                  
                  const SizedBox(height: 8),
                  
                  // ── Safety Notice ────────────────────────
                  _buildSafetyNotice(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Live LED Indicators
  // ═══════════════════════════════════════════════════════════

  Widget _liveLEDs(CraneController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ConnectionColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ConnectionColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ledIndicator(
            label: 'ESTOP',
            active: controller.ledEstop,
            color: AppColors.eStopColor,
            pinName: 'R0_0',
          ),
          _ledIndicator(
            label: 'UP',
            active: controller.ledUp || _upPressed,
            color: AppColors.upColor,
            pinName: 'Q0.1',
          ),
          _ledIndicator(
            label: 'DOWN',
            active: controller.ledDown || _downPressed,
            color: AppColors.downColor,
            pinName: 'Q0.2',
          ),
          // Spacer for visual balance (no FAST)
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: ConnectionColors.primarySoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'HOLD-TO-RUN',
              style: TextStyle(
                color: ConnectionColors.primary,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ledIndicator({
    required String label,
    required Color color,
    required bool active,
    required String pinName,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: active ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 300),
          builder: (context, value, child) {
            return Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: active ? color : Colors.grey.shade300,
                shape: BoxShape.circle,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: color.withAlpha(153),
                          blurRadius: 6 * value,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          pinName,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: ConnectionColors.textSecondary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: active ? color : ConnectionColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Status Bar
  // ═══════════════════════════════════════════════════════════

  Widget _buildStatusBar(CraneController controller) {
    final Color c;
    final String status;
    
    if (controller.estopLatched) {
      c = AppColors.eStopColor;
      status = 'EMERGENCY STOP';
    } else if (_upPressed) {
      c = AppColors.upColor;
      status = 'HOISTING UP — HOLD TO RUN';
    } else if (_downPressed) {
      c = AppColors.downColor;
      status = 'HOISTING DOWN — HOLD TO RUN';
    } else {
      c = AppColors.idleColor;
      status = 'IDLE — PRESS AND HOLD TO OPERATE';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withAlpha(100)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              boxShadow: (_upPressed || _downPressed)
                  ? [BoxShadow(color: c.withAlpha(128), blurRadius: 6)]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            status,
            style: TextStyle(
              color: c,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Safety Notice
  // ═══════════════════════════════════════════════════════════

  Widget _buildSafetyNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ConnectionColors.warning.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ConnectionColors.warning.withAlpha(50)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.safety_check_rounded, size: 14, color: ConnectionColors.warning),
          SizedBox(width: 6),
          Text(
            'DEADMAN CONTROL: Release button to stop immediately',
            style: TextStyle(
              color: ConnectionColors.warning,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // E-Stop Button
  // ═══════════════════════════════════════════════════════════

  Widget _buildEStopButton() {
    return GestureDetector(
      onTap: _onEStopTap,
      child: Container(
        width: double.infinity,
        height: 58,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6B0000), AppColors.eStopColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.eStopColor.withAlpha(100),
              blurRadius: 14,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(31),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withAlpha(64), width: 2),
              ),
              child: const Icon(
                Icons.power_settings_new,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EMERGENCY STOP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  'Tap to stop all crane operations',
                  style: TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // E-Stop Reset Section
  // ═══════════════════════════════════════════════════════════

  Widget _buildResetSection() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.eStopColor.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.eStopColor.withAlpha(130),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: AppColors.eStopColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EMERGENCY STOP ACTIVE',
                      style: TextStyle(
                        color: AppColors.eStopColorLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      'All crane controls are locked',
                      style: TextStyle(
                        color: ConnectionColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: EStopSwipeButton(
            onActivated: () {
              _onResetEStopTap();
            },
            instructionTitle: 'SWIPE TO RESET E-STOP',
            instructionSubtitle: 'Slide right to clear emergency lockout',
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Deadman Hold-to-Run Button
// ═══════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════
// Deadman Hold-to-Run Button (FIXED)
// ═══════════════════════════════════════════════════════════

class _DeadmanButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color colorLight;
  final bool isPressed;
  final bool isDisabled;
  final VoidCallback onPressed;
  final VoidCallback onReleased;

  const _DeadmanButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.colorLight,
    required this.isPressed,
    required this.isDisabled,
    required this.onPressed,
    required this.onReleased,
  });

  @override
  State<_DeadmanButton> createState() => _DeadmanButtonState();
}

// ✅ Use TickerProviderStateMixin (not SingleTickerProviderStateMixin)
class _DeadmanButtonState extends State<_DeadmanButton>
    with TickerProviderStateMixin {
  
  late final AnimationController _pressAnim;
  late final Animation<double> _scaleAnim;
  late final AnimationController _glowAnim;
  late final Animation<double> _glowOpacity;

  @override
  void initState() {
    super.initState();
    
    _pressAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _pressAnim, curve: Curves.easeIn),
    );
    
    _glowAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _glowOpacity = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _glowAnim, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(_DeadmanButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPressed && !oldWidget.isPressed) {
      _pressAnim.forward();
      _glowAnim.repeat(reverse: true);
    } else if (!widget.isPressed && oldWidget.isPressed) {
      _pressAnim.reverse();
      _glowAnim.stop();
      _glowAnim.reset();
    }
  }

  @override
  void dispose() {
    _pressAnim.dispose();
    _glowAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isPressed && !widget.isDisabled;
    final isDisabled = widget.isDisabled;

    return Listener(
      onPointerDown: (_) {
        if (isDisabled) return;
        widget.onPressed();
      },
      onPointerUp: (_) {
        widget.onReleased();
      },
      onPointerCancel: (_) {
        widget.onReleased();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_pressAnim, _glowAnim]),
        builder: (context, child) {
          final scale = widget.isPressed ? _scaleAnim.value : 1.0;
          final glow = widget.isPressed ? _glowOpacity.value : 0.0;
          
          return Transform.scale(
            scale: scale,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: isActive
                    ? LinearGradient(
                        colors: [widget.color, widget.colorLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isActive
                    ? null
                    : isDisabled
                        ? AppColors.disabled.withAlpha(50)
                        : ConnectionColors.surfaceAlt,
                border: Border.all(
                  color: isActive
                      ? widget.colorLight
                      : isDisabled
                          ? AppColors.disabled
                      : ConnectionColors.border,
                  width: isActive ? 3 : 1.5,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: widget.color.withAlpha(128),
                          blurRadius: 20 + (10 * glow),
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: widget.color.withAlpha(50),
                          blurRadius: 4,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withAlpha(35),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icon
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isActive ? 72 : 64,
                      height: isActive ? 72 : 64,
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white.withAlpha(40)
                            : widget.color.withAlpha(20),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isActive
                              ? Colors.white.withAlpha(100)
                              : widget.color.withAlpha(50),
                          width: isActive ? 2.5 : 1.5,
                        ),
                      ),
                      child: Icon(
                        widget.icon,
                        color: isActive
                            ? Colors.white
                            : isDisabled
                                ? AppColors.disabled
                                : widget.color,
                        size: isActive ? 36 : 30,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Label
                    Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isActive
                            ? Colors.white
                            : isDisabled
                                ? AppColors.disabled
                                : ConnectionColors.textPrimary,
                        fontSize: isActive ? 18 : 16,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Instruction text
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        color: isActive
                            ? Colors.white.withAlpha(200)
                            : isDisabled
                                ? AppColors.disabled
                                : ConnectionColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                      child: Text(
                        isActive ? 'RELEASE TO STOP' : 'HOLD TO RUN',
                      ),
                    ),
                    // Active indicator bar
                    const SizedBox(height: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isActive ? 48 : 24,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
