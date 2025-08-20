import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
import pandas as pd
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger(__name__)

class RecipeRecommender:
    def __init__(self):
        self.recipes = pd.DataFrame(columns=['id', 'name', 'ingredients', 'instructions'])
        self.user_preferences = {}
        self.vectorizer = TfidfVectorizer(
            stop_words='english',
            min_df=1,
            max_df=1.0,
            token_pattern=r'(?u)\b\w+\b',
            ngram_range=(1, 2)  # Allow both single words and pairs of words
        )
        self.recipe_vectors = None
        self.batch_size = 1000  # Process recipes in batches
        self.current_batch = []
        self.vectorizer_ready = False  # Flag to track if vectorizer is ready
        logger.info("Recipe recommender system initialized")
        
    def add_recipe(self, recipe_id, name, ingredients, instructions):
        """Add a new recipe to the system"""
        try:
            # Ensure ingredients is a list of strings
            if isinstance(ingredients, str):
                ingredients = [ingredients]
            elif not isinstance(ingredients, list):
                ingredients = []
            
            # Clean and process ingredients
            processed_ingredients = [str(ing).strip().lower() for ing in ingredients if str(ing).strip()]
            
            if not processed_ingredients:
                logger.warning(f"Recipe {recipe_id} has no valid ingredients")
                return
            
            # Log recipe details
            logger.info(f"Adding recipe: {name}")
            logger.info(f"Recipe ID: {recipe_id}")
            logger.info(f"Number of ingredients: {len(processed_ingredients)}")
            logger.info(f"Sample ingredients: {processed_ingredients[:5]}")
            
            # Add to current batch
            self.current_batch.append({
                'id': recipe_id,
                'name': name,
                'ingredients': ' '.join(processed_ingredients),
                'instructions': instructions
            })
            
            # If batch is full, process it
            if len(self.current_batch) >= self.batch_size:
                logger.info(f"Batch full ({len(self.current_batch)} recipes), processing...")
                self._process_batch()
                
        except Exception as e:
            logger.error(f"Error adding recipe: {str(e)}")
            logger.error(f"Error details: {type(e).__name__}: {str(e)}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
    
    def _process_batch(self):
        """Process the current batch of recipes"""
        if not self.current_batch:
            return
            
        try:
            # Convert batch to DataFrame
            batch_df = pd.DataFrame(self.current_batch)
            
            # Log batch details
            logger.info(f"Processing batch of {len(self.current_batch)} recipes")
            logger.info(f"Total recipes before batch: {len(self.recipes)}")
            
            # Add to main recipes DataFrame
            self.recipes = pd.concat([self.recipes, batch_df], ignore_index=True)
            
            # Log recipe statistics
            logger.info(f"Total recipes after batch: {len(self.recipes)}")
            logger.info(f"Sample recipe names in batch: {batch_df['name'].head(3).tolist()}")
            
            # Update vectors for all recipes
            self._update_vectors()
            
            logger.info(f"Processed batch. Total recipes: {len(self.recipes)}")
            
            # Clear the batch
            self.current_batch = []
            
        except Exception as e:
            logger.error(f"Error processing batch: {str(e)}")
            logger.error(f"Error details: {type(e).__name__}: {str(e)}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
    
    def track_user_behavior(self, user_id, recipe_id, ingredients_used):
        """Track which ingredients a user has used"""
        try:
            if user_id not in self.user_preferences:
                self.user_preferences[user_id] = set()
            
            # Add ingredients to user's preferences
            for ingredient in ingredients_used:
                ingredient = str(ingredient).strip().lower()
                if ingredient:
                    self.user_preferences[user_id].add(ingredient)
            
            logger.info(f"Tracked {len(ingredients_used)} ingredients for user {user_id}")
            logger.info(f"User {user_id} now has {len(self.user_preferences[user_id])} total ingredients")
            
        except Exception as e:
            logger.error(f"Error tracking behavior: {str(e)}")
            logger.error(f"Error details: {type(e).__name__}: {str(e)}")
                
    def _update_vectors(self):
        """Update the TF-IDF vectors for all recipes"""
        try:
            if not self.recipes.empty:
                # Get all recipe ingredients
                all_ingredients = self.recipes['ingredients'].tolist()
                
                # Fit and transform all recipes at once
                self.recipe_vectors = self.vectorizer.fit_transform(all_ingredients)
                
                # Get vocabulary information
                vocabulary = self.vectorizer.get_feature_names_out()
                logger.info(f"Updated vectors for {len(self.recipes)} recipes")
                logger.info(f"Vectorizer features: {len(vocabulary)}")
                logger.info(f"Sample vocabulary words: {list(vocabulary[:10])}")
                
                # Log some statistics about the vectors
                if self.recipe_vectors is not None:
                    logger.info(f"Recipe vectors shape: {self.recipe_vectors.shape}")
                    logger.info(f"Average non-zero elements per recipe: {self.recipe_vectors.nnz / len(self.recipes):.2f}")
                
                # Mark vectorizer as ready
                self.vectorizer_ready = True
                logger.info("Vectorizer is now ready for use")
                
        except Exception as e:
            logger.error(f"Error updating vectors: {str(e)}")
            logger.error(f"Error details: {type(e).__name__}: {str(e)}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            
    def get_recommendations(self, user_id, n=5):
        """Get recipe recommendations for a user"""
        try:
            logger.info(f"Getting recommendations for user {user_id}")
            
            # Check if user exists
            if user_id not in self.user_preferences:
                logger.warning(f"User {user_id} not found in user_preferences")
                return {
                    'error': 'User not found',
                    'message': f'User {user_id} has not tracked any recipes yet',
                    'exists': False
                }
            
            # Get user's ingredient preferences
            user_ingredients = self.user_preferences[user_id]
            logger.info(f"User {user_id} has {len(user_ingredients)} tracked ingredients")
            logger.info(f"User ingredients: {user_ingredients}")
            
            # Check if we have any recipes
            if self.recipes.empty:
                logger.warning("No recipes available for recommendations")
                return {
                    'error': 'No recipes available',
                    'message': 'The system has no recipes loaded',
                    'exists': True
                }
            
            # Get user's ingredient vector
            user_vector = self._get_user_vector(user_id)
            if user_vector is None:
                logger.warning(f"Could not generate user vector for {user_id}")
                return {
                    'error': 'Invalid user vector',
                    'message': 'Could not generate recommendations for this user',
                    'exists': True
                }
            
            logger.info(f"User vector shape: {user_vector.shape}")
            
            # Calculate similarities with all recipes
            similarities = []
            for idx, recipe in self.recipes.iterrows():
                try:
                    recipe_id = recipe['id']
                    recipe_ingredients = recipe['ingredients']
                    
                    # Ensure recipe ingredients are in the correct format
                    if isinstance(recipe_ingredients, str):
                        recipe_ingredients = [recipe_ingredients]
                    elif not isinstance(recipe_ingredients, list):
                        recipe_ingredients = []
                    
                    # Convert recipe ingredients to text
                    recipe_text = ' '.join(recipe_ingredients)
                    
                    # Vectorize recipe
                    recipe_vector = self.vectorizer.transform([recipe_text])
                    
                    # Calculate similarity
                    similarity = cosine_similarity(user_vector, recipe_vector)[0][0]
                    similarities.append((recipe_id, similarity))
                    
                except Exception as e:
                    logger.error(f"Error processing recipe {recipe_id}: {str(e)}")
                    continue
            
            if not similarities:
                logger.warning("No similarities calculated - no valid recipe vectors")
                return {
                    'error': 'No similarities found',
                    'message': 'Could not find similar recipes',
                    'exists': True
                }
            
            logger.info(f"Calculated similarities for {len(similarities)} recipes")
            
            # Sort by similarity and get top n
            similarities.sort(key=lambda x: x[1], reverse=True)
            top_n = similarities[:n]
            
            logger.info(f"Top {n} recipe similarities: {top_n}")
            
            # Get recipe details
            recommendations = []
            for recipe_id, similarity in top_n:
                recipe = self.recipes[self.recipes['id'] == recipe_id].iloc[0]
                recommendations.append({
                    'id': recipe_id,
                    'name': recipe['name'],
                    'ingredients': recipe['ingredients'].split(),
                    'similarity': float(similarity)
                })
            
            logger.info(f"Generated {len(recommendations)} recommendations")
            return {
                'exists': True,
                'recommendations': recommendations,
                'user_ingredients': list(user_ingredients)
            }
            
        except Exception as e:
            logger.error(f"Error getting recommendations: {str(e)}")
            logger.error(f"Error details: {type(e).__name__}: {str(e)}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            return {
                'error': 'Internal server error',
                'message': str(e),
                'exists': False
            }
        
    def get_all_recipes(self):
        """Get all recipes in the system"""
        return self.recipes.to_dict('records')

    def _get_user_vector(self, user_id):
        """Get the vector representation of a user's ingredient preferences"""
        try:
            logger.info(f"Generating user vector for {user_id}")
            
            if not self.vectorizer_ready:
                logger.warning("Vectorizer not ready yet, waiting for recipe processing to complete")
                return None
            
            if user_id not in self.user_preferences:
                logger.warning(f"User {user_id} not found in user_preferences")
                return None
            
            # Get user's ingredient preferences
            user_ingredients = self.user_preferences[user_id]
            logger.info(f"User {user_id} has {len(user_ingredients)} tracked ingredients")
            logger.debug(f"User ingredients: {user_ingredients}")
            
            if not user_ingredients:
                logger.warning(f"No ingredients tracked for user {user_id}")
                return None
            
            # Convert ingredients to text for vectorization
            ingredients_text = ' '.join(user_ingredients)
            logger.info(f"User ingredients text: {ingredients_text}")
            
            # Get the vocabulary from the vectorizer
            vocabulary = self.vectorizer.get_feature_names_out()
            logger.info(f"Vectorizer vocabulary size: {len(vocabulary)}")
            
            # Check if any user ingredients are in the vocabulary
            user_words = set(ingredients_text.lower().split())
            matching_words = user_words.intersection(vocabulary)
            logger.info(f"Found {len(matching_words)} matching words in vocabulary")
            logger.info(f"Matching words: {matching_words}")
            
            if not matching_words:
                logger.warning("No matching words found between user ingredients and vocabulary")
                return None
            
            # Vectorize ingredients using the existing vectorizer
            try:
                user_vector = self.vectorizer.transform([ingredients_text])
                logger.info(f"Generated user vector with shape: {user_vector.shape}")
                logger.debug(f"User vector non-zero elements: {user_vector.nnz}")
                
                # Check if the vector is empty (all zeros)
                if user_vector.nnz == 0:
                    logger.warning("Generated user vector is empty (all zeros)")
                    return None
                
                # Get the non-zero elements and their values
                non_zero_indices = user_vector.nonzero()[1]
                non_zero_values = user_vector.data
                logger.info(f"Non-zero elements: {len(non_zero_indices)}")
                
                # Log some of the matching words and their values
                for idx, value in zip(non_zero_indices[:5], non_zero_values[:5]):
                    word = vocabulary[idx]
                    logger.info(f"Word '{word}' has value {value}")
                
                return user_vector
                
            except Exception as e:
                logger.error(f"Error vectorizing user ingredients: {str(e)}")
                logger.error(f"Error details: {type(e).__name__}: {str(e)}")
                return None
            
        except Exception as e:
            logger.error(f"Error generating user vector: {str(e)}")
            logger.error(f"Error details: {type(e).__name__}: {str(e)}")
            import traceback
            logger.error(f"Traceback: {traceback.format_exc()}")
            return None 