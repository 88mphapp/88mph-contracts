const requireNoCache = require("./requireNoCache");
const config = requireNoCache("../deploy-configs/get-network-config");

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const mphAddress = config.isEthereum
    ? config.mph
    : (await get("MPHToken")).address;
  const deployResult = await deploy("Vesting02", {
    from: deployer,
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [mphAddress, "Vested MPH", "veMPH"]
        }
      }
    }
  });
  if (deployResult.newlyDeployed) {
    log(`Vesting02 deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["Vesting02"];
module.exports.dependencies = config.isEthereum ? [] : ["MPHToken"];
