const { ObjectId } = require('mongodb');
const getDbClient = require('../config/db');

exports.toggleLike = async (req, res) => {
  try {
    const { recipeId } = req.params;
    const userId = req.user.userId;
    const db = await getDbClient();
    const existingLike = await db.collection('likes').findOne({
      userId: new ObjectId(userId),
      recipeId: recipeId
    });
    if (existingLike) {
      await db.collection('likes').deleteOne({ userId: new ObjectId(userId), recipeId: recipeId });
      res.json({ liked: false });
    } else {
      await db.collection('likes').insertOne({ userId: new ObjectId(userId), recipeId: recipeId, createdAt: new Date() });
      res.json({ liked: true });
    }
  } catch (error) {
    res.status(500).json({ message: 'Failed to toggle like' });
  }
};

exports.isLiked = async (req, res) => {
  try {
    const { recipeId } = req.params;
    const userId = req.user.userId;
    const db = await getDbClient();
    const like = await db.collection('likes').findOne({ userId: userId, recipeId: recipeId });
    res.json({ isLiked: !!like });
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
};

exports.getLikedRecipes = async (req, res) => {
  try {
    const userId = req.user.userId;
    const db = await getDbClient();
    const likedRecipes = await db.collection('likes').aggregate([
      { $match: { userId: new ObjectId(userId) } },
      {
        $lookup: {
          from: "recipes",
          localField: "recipeId",
          foreignField: "_id",
          as: "recipe"
        }
      },
      { $unwind: "$recipe" },
      {
        $addFields: {
          "recipe.likedAt": "$createdAt"
        }
      },
      {
        $replaceRoot: { newRoot: "$recipe" }
      },
      { $sort: { likedAt: -1 } }
    ]).toArray();
    res.json(likedRecipes);
  } catch (error) {
    res.status(500).json({ message: 'Failed to get liked recipes', error: error.message });
  }
}; 