import 'package:flutter/material.dart';

class ProfilePicture extends StatelessWidget {
  final double size;
  final String? imageUrl;
  final VoidCallback? onRemove;

  const ProfilePicture({
    Key? key,
    this.size = 100,
    this.imageUrl,
    this.onRemove,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[200],
          ),
          child:
              imageUrl != null && imageUrl!.isNotEmpty
                  ? ClipOval(
                    child: Image.network(
                      imageUrl!,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) => Icon(
                            Icons.account_circle,
                            size: size * 0.9,
                            color: Colors.grey[600],
                          ),
                    ),
                  )
                  : Center(
                    child: Icon(
                      Icons.account_circle,
                      size: size * 0.9,
                      color: Colors.grey[600],
                    ),
                  ),
        ),
        if (imageUrl != null && imageUrl!.isNotEmpty && onRemove != null)
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 2)],
                ),
                child: const Icon(Icons.close, size: 20, color: Colors.red),
              ),
            ),
          ),
      ],
    );
  }
}
