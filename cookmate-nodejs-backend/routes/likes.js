const express = require('express');
const router = express.Router();
const likeController = require('../controllers/likeController');
const authenticateToken = require('../middlewares/auth');

router.post('/:recipeId/toggle-like', authenticateToken, likeController.toggleLike);
router.get('/:recipeId/is-liked', authenticateToken, likeController.isLiked);

module.exports = router;
