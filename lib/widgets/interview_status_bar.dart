import 'package:flutter/material.dart';
import '../models/models.dart';

class InterviewStatusBar extends StatelessWidget {
  final List<InterviewPoint> points;
  final bool hasLock;

  const InterviewStatusBar({
    super.key,
    required this.points,
    required this.hasLock,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'ready':
        return Colors.green;
      case 'preparing':
        return Colors.blue;
      case 'not_ready':
        return Colors.grey;
      default:
        return Colors.red.shade300;
    }
  }

  String _statusIcon(String status) {
    switch (status) {
      case 'ready':
        return '🟢';
      case 'preparing':
        return '🟡';
      case 'not_ready':
        return '🔵';
      default:
        return '🔴';
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'ready':
        return '就绪';
      case 'preparing':
        return '准备中';
      case 'not_ready':
        return '未就绪';
      default:
        return '离线';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Container(
        height: 60,
        color: Colors.grey.shade800,
        child: const Center(
          child: Text('暂无采访点', style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    return Container(
      height: 60,
      color: Colors.grey.shade800,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: points.length,
        itemBuilder: (context, index) {
          final point = points[index];
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _statusColor(point.status).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _statusColor(point.status),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _statusIcon(point.status),
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 6),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      point.pointName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _statusText(point.status),
                      style: TextStyle(
                        color: _statusColor(point.status),
                        fontSize: 10,
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
}
