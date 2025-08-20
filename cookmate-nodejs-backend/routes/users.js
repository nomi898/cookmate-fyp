const express = require('express');
const router = express.Router();
const userController = require('../controllers/userController');
const authenticateToken = require('../middlewares/auth');
const getDbClient = require('../config/db');
const { ObjectId } = require('mongodb');

router.get('/stats', authenticateToken, userController.getUserStats);
router.get('/recipes', authenticateToken, userController.getUserRecipes);
router.get('/liked-recipes', authenticateToken, userController.getUserLikedRecipes);
router.get('/:userId/searches', userController.getRecentSearches);
router.post('/:userId/searches', userController.saveSearch);

// GET /api/users/:userId/liked-recipes
router.get('/:userId/liked-recipes', async (req, res) => {
  try {
    const userId = req.params.userId;
    const db = await getDbClient();

    const likedRecipes = await db.collection('likes').aggregate([
      { $match: { userId: new ObjectId(userId) } },
      {
        $addFields: {
          recipeObjId: { $toObjectId: "$recipeId" }
        }
      },
      {
        $lookup: {
          from: "recipes",
          localField: "recipeObjId",
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
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Add user profile update and profile picture removal routes
router.patch('/me', authenticateToken, userController.updateUserProfile);
router.delete('/me/profile-picture', authenticateToken, userController.removeProfilePicture);
// Add route to get current authenticated user's info
router.get('/me', authenticateToken, userController.getCurrentUser);

module.exports = router;
