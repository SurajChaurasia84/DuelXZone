import 'package:flutter/material.dart';
import 'coin_service.dart';
import 'coins_screen.dart';
import 'screen_constants.dart';

class CoinBadge extends StatelessWidget {
  const CoinBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: CoinService.coinStream(),
      builder: (context, snapshot) {
        final coins = snapshot.data ?? 0;

        return GestureDetector(
          onTap: () {
            final isOnCoinsScreen = context.findAncestorWidgetOfExactType<CoinsScreen>() != null;
            if (!isOnCoinsScreen) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CoinsScreen(),
                ),
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: primaryColor.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.monetization_on_rounded,
                size: 18,
                color: primaryColor,
              ),
              const SizedBox(width: 6),
              Text(
                '$coins',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      );
    },
  );
}
}
