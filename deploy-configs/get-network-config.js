const fs = require("fs");
const networkName = JSON.parse(fs.readFileSync("deploy-configs/config.json"))
  .network;
const config = JSON.parse(
  fs.readFileSync(`deploy-configs/networks/${networkName}.json`)
);
module.exports = config;
