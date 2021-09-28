const _invalidateRequireCacheForFile = function(filePath) {
  delete require.cache[require.resolve(filePath)];
};

module.exports = function(filePath) {
  _invalidateRequireCacheForFile(filePath);
  return require(filePath);
};
