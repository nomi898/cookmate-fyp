import 'package:flutter/material.dart';
import 'package:cookmate/pages/homescreen.dart';
import 'package:cookmate/pages/detailrecipe.dart';
import 'package:cookmate/config/api_config.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FoodCard extends StatelessWidget {
  final Recipe recipe;
  final bool compact;
  final String? imageUrl;

  const FoodCard({
    super.key,
    required this.recipe,
    this.compact = false,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final displayUrl =
        imageUrl != null && imageUrl!.isNotEmpty
            ? imageUrl!
            : (recipe.imageUrl ?? '');
    return Column(
      children: [
        if (displayUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: displayUrl,
            height: compact ? 80 : 180,
            width: compact ? 140 : double.infinity,
            fit: BoxFit.cover,
            placeholder:
                (context, url) => Center(child: CircularProgressIndicator()),
            errorWidget:
                (context, url, error) =>
                    Icon(Icons.image_not_supported, size: compact ? 30 : 50),
          )
        else
          Icon(Icons.image_not_supported, size: compact ? 30 : 50),
        Padding(
          padding: EdgeInsets.all(compact ? 8.0 : 12.0),
          child: Text(
            recipe.title ?? 'No Title',
            style: TextStyle(
              fontSize: compact ? 10 : 15,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
          ),
        ),
        // ... other fields if needed
      ],
    );
  }
}
