import 'package:flutter/material.dart';

class StatusPill extends StatefulWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool isPulsing;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.isPulsing = true,
  });

  @override
  State<StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<StatusPill> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: widget.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isPulsing)
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, child) {
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withOpacity(_pulseAnim.value),
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withOpacity(0.6 * _pulseAnim.value),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                );
              },
            )
          else if (widget.icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(widget.icon, size: 13, color: widget.color),
            ),
          Text(
            widget.label,
            style: TextStyle(
              color: widget.color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
