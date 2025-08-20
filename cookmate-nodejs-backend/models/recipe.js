const getDbClient = require('../config/db');
const { ObjectId } = require('mongodb');

exports.findAllRecipes = async () => {
  const db = await getDbClient();
  return db.collection('recipes').find({}).toArray();
};

exports.findRecipeById = async (id) => {
  const db = await getDbClient();
  return db.collection('recipes').findOne({ _id: new ObjectId(id) });
};

exports.createRecipe = async (recipe) => {
  const db = await getDbClient();
  return db.collection('recipes').insertOne(recipe);
};

exports.deleteRecipeById = async (id) => {
  const db = await getDbClient();
  return db.collection('recipes').deleteOne({ _id: new ObjectId(id) });
};

exports.searchRecipesByIngredients = async (terms) => {
  const db = await getDbClient();
  const ingredientQueries = terms.map(term => ({ Cleaned_Ingredients: { $regex: term, $options: 'i' } }));
  return db.collection('recipes').find({ $and: ingredientQueries }).toArray();
};
