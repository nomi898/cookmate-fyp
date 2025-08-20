const getDbClient = require('../config/db');
const { ObjectId } = require('mongodb');

exports.uploadImage = async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ message: 'No file uploaded' });
    }
    const imageUrl = `${req.protocol}://${req.get('host')}/uploads/${req.file.filename}`;
    res.json({ message: 'File uploaded successfully', imageUrl });
  } catch (error) {
    res.status(500).json({ message: 'Failed to upload file' });
  }
};

exports.uploadProfilePicture = async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ message: 'No file uploaded' });
    }
    const imageUrl = `${req.protocol}://${req.get('host')}/uploads/${req.file.filename}`;
    const db = await getDbClient();
    await db.collection('users').updateOne(
      { _id: new ObjectId(req.user.userId) },
      { $set: { profilePicture: imageUrl } }
    );
    const updatedUser = await db.collection('users').findOne(
      { _id: new ObjectId(req.user.userId) },
      { projection: { password: 0 } }
    );
    res.json({ message: 'Profile picture updated successfully', imageUrl, user: updatedUser });
  } catch (error) {
    res.status(500).json({ message: 'Failed to update profile picture' });
  }
};

exports.createRecipe = async (req, res) => {
  try {
    // Get the filename from multer
    const filename = req.file.filename; // e.g., "1751742389843.jpg"
    // Build the image path for the database
    const imagePath = `${filename}`;

    // Build the recipe object
    const recipe = {
      Title: req.body.Title,
      Cleaned_Ingredients: req.body.Cleaned_Ingredients,
      Instructions: req.body.Instructions,
      image: imagePath, // <-- Save the correct path here
      userId: req.user.userId,
      createdAt: new Date()
    };

    // Save to database
    const db = await getDbClient();
    await db.collection('recipes').insertOne(recipe);

    res.status(201).json({ message: 'Recipe created successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Failed to create recipe' });
  }
};
