# Recipe Recommendation System

A content-based recipe recommendation system that suggests recipes based on user's ingredient preferences and usage patterns.

## Features
- Content-based recommendation using ingredients
- User behavior tracking
- REST API endpoints for Flutter app integration
- Recipe similarity scoring based on ingredients

## Setup
1. Create a virtual environment:
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Run the server:
```bash
python app.py
```

## API Endpoints
- `POST /api/recommend`: Get recipe recommendations based on user preferences
- `POST /api/track`: Track user behavior and ingredient usage
- `GET /api/recipes`: Get all available recipes 