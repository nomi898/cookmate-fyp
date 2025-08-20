const getDbClient = require('../config/db');
const { ObjectId } = require('mongodb');

exports.findLikesByUser = async (userId) => {
  const db = await getDbClient();
  return db.collection('likes').find({ userId: new ObjectId(userId) }).toArray();
};

exports.toggleLike = async (userId, recipeId) => {
  const db = await getDbClient();
  const existing = await db.collection('likes').findOne({ userId: new ObjectId(userId), recipeId });
  if (existing) {
    await db.collection('likes').deleteOne({ userId: new ObjectId(userId), recipeId });
    return false;
  } else {
    await db.collection('likes').insertOne({ userId: new ObjectId(userId), recipeId, createdAt: new Date() });
    return true;
  }
};

exports.isRecipeLikedByUser = async (userId, recipeId) => {
  const db = await getDbClient();
  const like = await db.collection('likes').findOne({ userId: new ObjectId(userId), recipeId });
  return !!like;
};
