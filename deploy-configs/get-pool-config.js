const poolName = require("./config.json").pool;
const config = require(`./pools/${poolName}.json`);
module.exports = config;
