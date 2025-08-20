const { MongoClient } = require('mongodb');

async function run() {
  const client = new MongoClient('mongodb://localhost:27017');
  await client.connect();
  const db = client.db('cookmate');
  const recipes = db.collection('recipes');

  const cursor = recipes.find({ image: { $exists: true, $type: 'string' } });
  let updated = 0;

  while (await cursor.hasNext()) {
    const recipe = await cursor.next();
    if (recipe.image) {
      // Extract just the filename
      const filename = recipe.image.split('/').pop();
      if (filename && filename !== recipe.image) {
        await recipes.updateOne(
          { _id: recipe._id },
          { $set: { image: filename } }
        );
        updated++;
      }
    }
  }

  console.log(`Updated ${updated} recipes.`);
  await client.close();
}

run();