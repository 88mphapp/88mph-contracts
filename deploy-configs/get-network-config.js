const networkName = require("./config.json").network;
const config = require(`./networks/${networkName}.json`);
module.exports = config;
