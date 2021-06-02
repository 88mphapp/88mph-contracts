const config = require("./config.json");
const poolName = config.pool;
const networkName = config.network;
const poolConfig = require(`./pools/${networkName}/${poolName}.json`);
module.exports = poolConfig;
