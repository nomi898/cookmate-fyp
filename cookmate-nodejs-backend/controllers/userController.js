const { ObjectId } = require('mongodb');
const getDbClient = require('../config/db');

exports.getUserStats = async (req, res) => {
  try {
    const db = await getDbClient();
    const userObjectId = new ObjectId(req.user.userId);
    const recipeCount = await db.collection('recipes').countDocuments({ userId: userObjectId });
    const likedCount = await db.collection('likes').countDocuments({ userId: userObjectId });
    res.json({ recipeCount, likedCount });
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
};

exports.getUserRecipes = async (req, res) => {
  try {
    const db = await getDbClient();
    const userObjectId = new ObjectId(req.user.userId);
    const recipes = await db.collection('recipes').find({ userId: userObjectId }).toArray();
    res.json(recipes);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
};

exports.getUserLikedRecipes = async (req, res) => {
  try {
    const db = await getDbClient();
    const userId = req.user.userId;
    const likes = await db.collection('likes').find({ userId: userId }).toArray();
    const recipeIds = likes.map(like => new ObjectId(like.recipeId));
    const recipes = await db.collection('recipes').find({ _id: { $in: recipeIds } }).toArray();
    res.json(recipes);
  } catch (error) {
    res.status(500).json({ message: 'Internal server error' });
  }
};

exports.getRecentSearches = async (req, res) => {
  try {
    const db = await getDbClient();
    const searches = await db.collection('user_searches')
      .find({ userId: req.params.userId })
      .sort({ timestamp: -1 })
      .limit(7)
      .toArray();
    const searchQueries = searches.map(s => s.query);
    res.json(searchQueries);
  } catch (error) {
    res.status(500).json({ message: 'Failed to fetch searches' });
  }
};

exports.saveSearch = async (req, res) => {
  try {
    const { userId } = req.params;
    const { query } = req.body;
    if (!query) {
      return res.status(400).json({ message: 'Search query is required' });
    }
    const db = await getDbClient();
    await db.collection('user_searches').insertOne({ userId, query, timestamp: new Date() });
    const searches = await db.collection('user_searches')
      .find({ userId })
      .sort({ timestamp: -1 })
      .toArray();
    if (searches.length > 7) {
      const searchesToDelete = searches.slice(7);
      await db.collection('user_searches').deleteMany({ _id: { $in: searchesToDelete.map(s => s._id) } });
    }
    res.status(201).json({ message: 'Search saved successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Failed to save search' });
  }
};

// Update user profile (name)
exports.updateUserProfile = async (req, res) => {
  try {
    const db = await getDbClient();
    const userId = req.user.userId;
    const { firstName, lastName } = req.body;
    if (!firstName && !lastName) {
      return res.status(400).json({ message: 'No name fields provided' });
    }
    const updateFields = {};
    if (firstName) updateFields.firstName = firstName;
    if (lastName) updateFields.lastName = lastName;
    await db.collection('users').updateOne(
      { _id: new ObjectId(userId) },
      { $set: updateFields }
    );
    const updatedUser = await db.collection('users').findOne(
      { _id: new ObjectId(userId) },
      { projection: { password: 0 } }
    );
    res.json({ message: 'Profile updated successfully', user: updatedUser });
  } catch (error) {
    res.status(500).json({ message: 'Failed to update profile' });
  }
};

// Remove profile picture
exports.removeProfilePicture = async (req, res) => {
  try {
    const db = await getDbClient();
    const userId = req.user.userId;
    // Optionally, delete the file from disk here if needed
    await db.collection('users').updateOne(
      { _id: new ObjectId(userId) },
      { $unset: { profilePicture: '' } }
    );
    const updatedUser = await db.collection('users').findOne(
      { _id: new ObjectId(userId) },
      { projection: { password: 0 } }
    );
    res.json({ message: 'Profile picture removed successfully', user: updatedUser });
  } catch (error) {
    res.status(500).json({ message: 'Failed to remove profile picture' });
  }
};

// Get current authenticated user's info
exports.getCurrentUser = async (req, res) => {
  try {
    const db = await getDbClient();
    const user = await db.collection('users').findOne(
      { _id: new ObjectId(req.user.userId) },
      { projection: { password: 0 } }
    );
    if (!user) return res.status(404).json({ message: 'User not found' });
    // Always return a profileImageUrl field
    let profileImageUrl = user.profilePicture;
    if (!profileImageUrl) {
      profileImageUrl = `${req.protocol}://${req.get('host')}/uploads/default-profile.png`;
    }
    res.json({ ...user, profileImageUrl });
  } catch (error) {
    res.status(500).json({ message: 'Failed to fetch user info' });
  }
};
