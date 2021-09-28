const fs = require("fs");
const config = JSON.parse(fs.readFileSync("deploy-configs/config.json"));
const poolName = config.pool;
const networkName = config.network;
const poolConfig = JSON.parse(
  fs.readFileSync(`deploy-configs/pools/${networkName}/${poolName}.json`)
);
module.exports = poolConfig;
