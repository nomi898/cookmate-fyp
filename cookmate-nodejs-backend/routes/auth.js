const express = require('express');
const router = express.Router();
const authController = require('../controllers/authController');

router.post('/register', authController.register);
router.post('/login', authController.login);
router.post('/reset-password-request', authController.resetPasswordRequest);
router.post('/reset-password/:token', authController.resetPassword);
router.post('/google', authController.googleSignIn);

module.exports = router;
