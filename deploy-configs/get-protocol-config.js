const config = require("./config.json");
const protocolName = config.protocol;
const networkName = config.network;
const protocolConfig = require(`./protocols/${networkName}/${protocolName}.json`);
module.exports = protocolConfig;
