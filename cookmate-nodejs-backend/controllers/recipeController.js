const { ObjectId } = require('mongodb');
const getDbClient = require('../config/db');

exports.getAllRecipes = async (req, res) => {
  try {
    const db = await getDbClient();
    const recipes = await db.collection('recipes')
      .find({})
      .project({
        title: 1,
        Title: 1,
        ingredients: 1,
        Ingredients: 1,
        instructions: 1,
        Instructions: 1,
        image: 1,
        Image_Name: 1,
        cleaned_ingredients: 1,
        Cleaned_Ingredients: 1,
        userId: 1,
        createdAt: 1
      })
      .toArray();
    const processedRecipes = recipes.map(recipe => {
      let imageFile = recipe.image || recipe.Image_Name || '';
      if (imageFile && !imageFile.startsWith('/uploads/')) {
        imageFile = `/uploads/images/FoodImages/${imageFile}`;
      }
      const imageUrl = imageFile ? `${req.protocol}://${req.get('host')}${imageFile}` : '';
      return { ...recipe, _id: recipe._id.toString(), imageUrl };
    });
    res.json(processedRecipes);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
};

exports.getRecipeById = async (req, res) => {
  try {
    const db = await getDbClient();
    const recipe = await db.collection('recipes').findOne({ _id: new ObjectId(req.params.id) });
    if (!recipe) {
      return res.status(404).json({ message: 'Recipe not found' });
    }
    let imageFile = recipe.image || recipe.Image_Name || '';
    if (imageFile && !imageFile.startsWith('/uploads/')) {
      imageFile = `/uploads/images/FoodImages/${imageFile}`;
    }
    const imageUrl = imageFile ? `${req.protocol}://${req.get('host')}${imageFile}` : '';
    const processedRecipe = {
      ...recipe,
      _id: recipe._id.toString(),
      Title: recipe.Title || '',
      Instructions: recipe.Instructions || '',
      Cleaned_Ingredients: recipe.Cleaned_Ingredients || [],
      imageUrl
    };
    res.json(processedRecipe);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
};

exports.createRecipe = async (req, res) => {
  try {
    const { Title, Cleaned_Ingredients, Instructions, image } = req.body;
    const userId = req.user.userId;
    if (!Title || !Cleaned_Ingredients || !Instructions) {
      return res.status(400).json({ message: 'Missing required fields' });
    }
    const db = await getDbClient();
    const recipe = {
      Title,
      Cleaned_Ingredients,
      Instructions,
      image,
      userId: new ObjectId(userId),
      createdAt: new Date()
    };
    const result = await db.collection('recipes').insertOne(recipe);
    res.status(201).json({
      message: 'Recipe created successfully',
      recipeId: result.insertedId
    });
  } catch (error) {
    res.status(500).json({ message: 'Failed to create recipe' });
  }
};

exports.deleteRecipe = async (req, res) => {
  try {
    const recipeId = req.params.recipeId;
    const db = await getDbClient();
    const recipe = await db.collection('recipes').findOne({ _id: new ObjectId(recipeId) });
    if (!recipe) {
      return res.status(404).json({ message: 'Recipe not found' });
    }
    const result = await db.collection('recipes').deleteOne({ _id: new ObjectId(recipeId) });
    if (result.deletedCount === 0) {
      return res.status(404).json({ message: 'Recipe not found' });
    }
    res.json({ message: 'Recipe deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Failed to delete recipe' });
  }
};

exports.searchRecipes = async (req, res) => {
  try {
    const { query } = req.query;
    if (!query) {
      return res.status(400).json({ message: 'Search query is required' });
    }
    const db = await getDbClient();
    const searchTerms = query.split(/[,\s]+/).map(term => term.trim()).filter(term => term.length > 0);
    const ingredientQueries = searchTerms.map(term => ({ Cleaned_Ingredients: { $regex: term, $options: 'i' } }));
    const searchCriteria = { $and: ingredientQueries };
    const recipes = await db.collection('recipes').find(searchCriteria).toArray();
    const processedRecipes = recipes.map(recipe => ({ ...recipe, _id: recipe._id.toString() }));
    res.json(processedRecipes);
  } catch (error) {
    res.status(500).json({ message: 'Failed to search recipes' });
  }
};

exports.checkLikes = async (req, res) => {
  try {
    const { recipeIds, userId } = req.body;
    if (!recipeIds || !userId) {
      return res.status(400).json({ message: 'Recipe IDs and User ID are required' });
    }
    const db = await getDbClient();
    const likes = await db.collection('likes').find({ recipeId: { $in: recipeIds }, userId: userId }).toArray();
    const likedRecipeIds = likes.map(like => like.recipeId);
    res.json({ likedRecipeIds });
  } catch (error) {
    res.status(500).json({ message: 'Failed to check likes' });
  }
};
