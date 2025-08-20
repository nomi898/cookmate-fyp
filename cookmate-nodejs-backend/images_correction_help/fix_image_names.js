const { MongoClient } = require('mongodb');

const url = 'mongodb://localhost:27017'; // or your connection string
const dbName = 'cookmate';

async function run() {
  const client = new MongoClient(url);
  await client.connect();
  const db = client.db(dbName);
  const recipes = db.collection('recipes');

  // Update all documents: set Image_Name = Title + ".jpg"
  const result = await recipes.updateMany(
    {},
    [
      {
        $set: {
          Image_Name: { $concat: ["$Title", ".jpg"] }
        }
      }
    ]
  );

  console.log(`Updated ${result.modifiedCount} recipes.`);
  await client.close();
}

run().catch(console.error);
