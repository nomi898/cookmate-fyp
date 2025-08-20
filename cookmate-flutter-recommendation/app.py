from flask import Flask, request, jsonify
from flask_cors import CORS
from recommender import RecipeRecommender
from pymongo import MongoClient
from bson import ObjectId
import os
import logging
import sys
from dotenv import load_dotenv
import threading
import time

# Set up logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('app.log')
    ]
)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

try:
    logger.info("Initializing Flask application...")
    app = Flask(__name__)
    
    # Configure CORS to allow all origins and methods
    CORS(app, resources={
        r"/api/*": {
            "origins": "*",
            "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
            "allow_headers": ["Content-Type"]
        }
    })

    # Initialize recommender
    logger.info("Initializing recipe recommender...")
    recommender = RecipeRecommender()

    # MongoDB connection
    MONGO_URL = os.getenv('MONGO_URL', 'mongodb://localhost:27017')
    DB_NAME = os.getenv('DB_NAME', 'cookmate')

    def get_db():
        try:
            logger.info(f"Connecting to MongoDB at {MONGO_URL}")
            client = MongoClient(MONGO_URL, serverSelectionTimeoutMS=5000)  # 5 second timeout
            db = client[DB_NAME]
            # Test the connection
            db.command('ping')
            logger.info("Successfully connected to MongoDB")
            return db
        except Exception as e:
            logger.error(f"Failed to connect to MongoDB: {str(e)}")
            logger.error("Please ensure MongoDB is running and accessible")
            raise

    def process_ingredients(ingredients):
        """Process ingredients list into a format suitable for TF-IDF"""
        if isinstance(ingredients, list):
            # Join ingredients with spaces and convert to lowercase
            return ' '.join(str(ingredient).lower() for ingredient in ingredients)
        elif isinstance(ingredients, str):
            # If it's a string, split by commas and process
            return ' '.join(ingredient.strip().lower() for ingredient in ingredients.split(','))
        return ''

    def fetch_recipes_from_mongodb():
        """Fetch recipes from MongoDB and add them to the recommender"""
        try:
            logger.info("Fetching recipes from MongoDB...")
            db = get_db()
            
            # Count total recipes first
            total_recipes = db.recipes.count_documents({})
            logger.info(f"Found {total_recipes} recipes in database")
            
            recipes = db.recipes.find(
                {},
                {
                    '_id': 1,
                    'Title': 1,
                    'Cleaned_Ingredients': 1,
                    'Instructions': 1,
                    'image': 1
                }
            )
            
            recipe_count = 0
            for recipe in recipes:
                try:
                    recipe_count += 1
                    if recipe_count % 100 == 0:
                        logger.info(f"Processed {recipe_count}/{total_recipes} recipes")
                    
                    # Process ingredients to ensure they're in the correct format
                    ingredients = recipe.get('Cleaned_Ingredients', [])
                    if isinstance(ingredients, str):
                        ingredients = [ingredients]
                    elif not isinstance(ingredients, list):
                        ingredients = []
                    
                    if not ingredients:
                        logger.warning(f"Recipe {recipe.get('_id')} has no ingredients")
                        continue
                    
                    recommender.add_recipe(
                        recipe_id=str(recipe['_id']),
                        name=recipe.get('Title', ''),
                        ingredients=ingredients,
                        instructions=recipe.get('Instructions', '')
                    )
                
                except Exception as e:
                    logger.error(f"Error processing recipe {recipe.get('_id')}: {str(e)}")
            
            # Process any remaining recipes in the last batch
            recommender._process_batch()
            logger.info(f"Successfully loaded all {recipe_count} recipes")
            
            # Start Flask server only after all recipes are loaded
            logger.info("All recipes loaded, starting Flask server...")
            start_flask_server()
            
            return True
        except Exception as e:
            logger.error(f"Error fetching recipes from MongoDB: {str(e)}")
            logger.error("Please check your MongoDB connection and database setup")
            return False

    def start_flask_server():
        """Start the Flask server"""
        try:
            logger.info("Starting Flask server...")
            logger.info("Server will be available at http://localhost:5002")
            
            print("\n" + "="*50)
            print("Flask server starting...")
            print("="*50 + "\n")
            
            app.run(
                debug=True,
                host='0.0.0.0',
                port=5002,
                use_reloader=False,
                threaded=True
            )
        except Exception as e:
            logger.error(f"Failed to start Flask server: {str(e)}")
            print(f"\nError starting server: {str(e)}")
            raise

    @app.route('/api/recommendations/<user_id>', methods=['GET'])
    def get_recommendations(user_id):
        """Get recipe recommendations for a user"""
        try:
            logger.info(f"Getting recommendations for user {user_id}")
            recommendations = recommender.get_recommendations(user_id)
            return jsonify(recommendations)
        except Exception as e:
            logger.error(f"Error getting recommendations: {str(e)}")
            return jsonify({'error': str(e)}), 500

    @app.route('/api/track', methods=['POST'])
    def track_user_behavior():
        """Track user behavior and ingredient preferences"""
        try:
            logger.info("Received tracking request")
            data = request.get_json()
            logger.debug(f"Request data: {data}")
            
            user_id = data.get('user_id')
            recipe_id = data.get('recipe_id')
            ingredients_used = data.get('ingredients_used', [])
            
            if not all([user_id, recipe_id, ingredients_used]):
                logger.warning("Missing required fields in request")
                return jsonify({'error': 'Missing required fields'}), 400
                
            logger.info(f"Tracking behavior for user {user_id}")
            logger.debug(f"Recipe ID: {recipe_id}")
            logger.debug(f"Ingredients used: {ingredients_used}")
            
            recommender.track_user_behavior(user_id, recipe_id, ingredients_used)
            logger.info("Successfully tracked user behavior")
            return jsonify({'message': 'Behavior tracked successfully'})
        except Exception as e:
            logger.error(f"Error tracking behavior: {str(e)}")
            logger.error(f"Error details: {type(e).__name__}: {str(e)}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            return jsonify({'error': str(e)}), 500

    @app.route('/api/recipes', methods=['GET'])
    def get_all_recipes():
        """Get all recipes in the system"""
        try:
            logger.info("Getting all recipes")
            recipes = recommender.get_all_recipes()
            return jsonify(recipes)
        except Exception as e:
            logger.error(f"Error getting recipes: {str(e)}")
            return jsonify({'error': str(e)}), 500

    @app.route('/api/refresh', methods=['POST'])
    def refresh_recipes():
        """Refresh recipes from MongoDB"""
        try:
            logger.info("Refreshing recipes")
            fetch_recipes_from_mongodb()
            return jsonify({'message': 'Recipes refreshed successfully'})
        except Exception as e:
            logger.error(f"Error refreshing recipes: {str(e)}")
            return jsonify({'error': str(e)}), 500

    @app.route('/api/users/<user_id>', methods=['GET'])
    def get_user_info(user_id):
        """Get information about a user and their tracked ingredients"""
        try:
            logger.info(f"Checking user {user_id}")
            if user_id not in recommender.user_preferences:
                return jsonify({
                    'exists': False,
                    'message': f'User {user_id} not found'
                }), 404
            
            user_ingredients = list(recommender.user_preferences[user_id])
            return jsonify({
                'exists': True,
                'user_id': user_id,
                'tracked_ingredients': user_ingredients,
                'ingredient_count': len(user_ingredients)
            })
        except Exception as e:
            logger.error(f"Error checking user: {str(e)}")
            return jsonify({'error': str(e)}), 500

    if __name__ == '__main__':
        try:
            logger.info("Starting recipe loading process...")
            fetch_recipes_from_mongodb()
        except Exception as e:
            logger.error(f"Fatal error during application startup: {str(e)}")
            raise

except Exception as e:
    logger.error(f"Fatal error during application startup: {str(e)}")
    raise 