const express = require('express');
const router = express.Router();
const recipeController = require('../controllers/recipeController');
const authenticateToken = require('../middlewares/auth');
const upload = require('../middlewares/upload');

router.get('/', recipeController.getAllRecipes);
router.get('/search', recipeController.searchRecipes);
router.get('/:id', recipeController.getRecipeById);
router.post('/', authenticateToken, upload.single('image'), recipeController.createRecipe);
router.delete('/:recipeId', authenticateToken, recipeController.deleteRecipe);
router.post('/check-likes', recipeController.checkLikes);

module.exports = router;
