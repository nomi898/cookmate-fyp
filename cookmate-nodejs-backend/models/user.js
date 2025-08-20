const getDbClient = require('../config/db');
const { ObjectId } = require('mongodb');

exports.findUserByEmail = async (email) => {
  const db = await getDbClient();
  return db.collection('users').findOne({ email });
};

exports.createUser = async (user) => {
  const db = await getDbClient();
  return db.collection('users').insertOne(user);
};

exports.updateUserById = async (id, update) => {
  const db = await getDbClient();
  return db.collection('users').updateOne({ _id: new ObjectId(id) }, update);
};

exports.findUserById = async (id) => {
  const db = await getDbClient();
  return db.collection('users').findOne({ _id: new ObjectId(id) });
};

// ...add more as needed
