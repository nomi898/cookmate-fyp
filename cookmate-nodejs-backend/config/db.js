const { MongoClient } = require('mongodb');

const url = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const dbName = process.env.DB_NAME || 'cookmate';

async function getDbClient() {
  const client = await MongoClient.connect(url);
  return client.db(dbName);
}

module.exports = getDbClient;
