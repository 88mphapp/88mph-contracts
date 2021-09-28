const fs = require("fs");
const config = JSON.parse(fs.readFileSync("deploy-configs/config.json"));
const protocolName = config.protocol;
const networkName = config.network;
const protocolConfig = JSON.parse(
  fs.readFileSync(
    `deploy-configs/protocols/${networkName}/${protocolName}.json`
  )
);
module.exports = protocolConfig;
