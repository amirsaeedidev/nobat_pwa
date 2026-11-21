import 'package:flutter/material.dart';

import '../../app/theme/app_palette.dart';
import '../utils/formatters.dart';
import '../../data/models/activity_log.dart';

/// یک ردیف از گزارش فعالیت.
class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.log, this.dense = false, this.showActor = true});

  final ActivityLog log;
  final bool dense;
  final bool showActor;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 7 : 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: dense ? 32 : 36,
            height: dense ? 32 : 36,
            decoration: BoxDecoration(
              color: log.type.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: log.type.color.withValues(alpha: 0.28)),
            ),
            child: Icon(log.type.icon, size: dense ? 15 : 17, color: log.type.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        log.title,
                        style: TextStyle(
                          fontSize: dense ? 12 : 12.5,
                          fontWeight: FontWeight.w700,
                          color: pal.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      Fmt.timeAgo(log.createdAt),
                      style: TextStyle(fontSize: 9.5, color: pal.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  log.description,
                  style: TextStyle(fontSize: dense ? 10.5 : 11, color: pal.textMuted, height: 1.7),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (log.entityName.isNotEmpty || log.operationType != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 2,
                      children: [
                        if (log.entityName.isNotEmpty)
                          Text(
                            '${log.entityName}${log.entityId.isNotEmpty ? ' • ${log.entityId}' : ''}',
                            style: TextStyle(fontSize: 9, color: pal.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (log.operationType != null)
                          Text(log.operationLabel, style: TextStyle(fontSize: 9, color: pal.textMuted)),
                        Text(
                          log.isReversible ? 'قابل بازگردانی' : 'غیرقابل بازگردانی',
                          style: TextStyle(fontSize: 9, color: log.isReversible ? pal.info : pal.danger),
                        ),
                      ],
                    ),
                  ),
                if (showActor)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      'توسط ${log.actor}',
                      style: TextStyle(fontSize: 9.5, color: pal.textSecondary.withValues(alpha: 0.8)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
