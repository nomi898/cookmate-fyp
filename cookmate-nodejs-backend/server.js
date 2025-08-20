require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');

const { requestLogger, structuredLogger } = require('./middlewares/logger');
const errorHandler = require('./middlewares/errorHandler');

const authRoutes = require('./routes/auth');
const recipeRoutes = require('./routes/recipes');
const userRoutes = require('./routes/users');
const likeRoutes = require('./routes/likes');
const uploadRoutes = require('./routes/uploads');

const app = express();

// Enable CORS for all routes
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Logging middleware
app.use(requestLogger);
app.use(structuredLogger);

// Serve uploaded files statically
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Mount routes
app.use('/api/auth', authRoutes);
app.use('/api/recipes', recipeRoutes);
app.use('/api/users', userRoutes);
app.use('/api/likes', likeRoutes);
app.use('/api/upload', uploadRoutes);

// Root route
app.get('/', (req, res) => {
  res.send('Welcome to the Cookmate API!');
});

// Global error handler
app.use(errorHandler);

// Start the server
const PORT = process.env.PORT || 3000;

// Debugging output before starting server
console.log('--- Cookmate Server Debug Info ---');
console.log('NODE_ENV:', process.env.NODE_ENV);
console.log('PORT:', PORT);
console.log('MONGODB_URI:', process.env.MONGODB_URI || process.env.DB_URI || 'Not set');
console.log('Current working directory:', process.cwd());
console.log('Environment variables loaded from .env:', Object.keys(process.env).filter(k => k.startsWith('COOKMATE_') || k.startsWith('MONGODB_') || k.startsWith('DB_')));
console.log('-----------------------------------');

try {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server is running on all network interfaces, port ${PORT}`);
    console.log(`Server URLs:`);
    console.log(`- Local: http://localhost:${PORT}`);
    console.log(`- Network: http://YOUR_IP:${PORT}`);
  });
} catch (err) {
  console.error('Failed to start server:', err);
  process.exit(1);
}
