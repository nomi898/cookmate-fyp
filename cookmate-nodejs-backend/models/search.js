const getDbClient = require('../config/db');

exports.saveUserSearch = async (userId, query) => {
  const db = await getDbClient();
  await db.collection('user_searches').insertOne({ userId, query, timestamp: new Date() });
  const searches = await db.collection('user_searches')
    .find({ userId })
    .sort({ timestamp: -1 })
    .toArray();
  if (searches.length > 7) {
    const searchesToDelete = searches.slice(7);
    await db.collection('user_searches').deleteMany({ _id: { $in: searchesToDelete.map(s => s._id) } });
  }
};

exports.getRecentUserSearches = async (userId) => {
  const db = await getDbClient();
  const searches = await db.collection('user_searches')
    .find({ userId })
    .sort({ timestamp: -1 })
    .limit(7)
    .toArray();
  return searches.map(s => s.query);
};
