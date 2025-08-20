const express = require('express');
const router = express.Router();
const upload = require('../middlewares/upload');
const uploadController = require('../controllers/uploadController');
const authenticateToken = require('../middlewares/auth');
const multer = require('multer');
const path = require('path');

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, 'uploads/');
  },
  filename: function (req, file, cb) {
    const filename = Date.now() + path.extname(file.originalname);
    cb(null, filename);
  }
});

const fileFilter = (req, file, cb) => {
  // Accept only image files
  if (file.mimetype.startsWith('image/')) {
    cb(null, true);
  } else {
    cb(new Error('Only image files are allowed!'), false);
  }
};

const uploadProfile = multer({ storage, fileFilter });
const uploadRecipe = multer({ storage, fileFilter });

router.post('/', upload.single('image'), uploadController.uploadImage);
router.post('/profile-picture', authenticateToken, upload.single('image'), uploadController.uploadProfilePicture);

module.exports = router;
