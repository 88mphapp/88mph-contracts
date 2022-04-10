const requireNoCache = require("./requireNoCache");
const config = requireNoCache("../deploy-configs/get-network-config");
const poolConfig = requireNoCache("../deploy-configs/get-pool-config");

const name = `${poolConfig.name}--YVaultMarket`;

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts,
}) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy(name, {
    from: deployer,
    contract: "YVaultMarket",
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            poolConfig.moneyMarketParams.vault,
            config.govTreasury,
            poolConfig.stablecoin,
          ],
        },
      },
    },
  });
  if (deployResult.newlyDeployed) {
    log(`${name} deployed at ${deployResult.address}`);
  }
};
module.exports.tags = [name];
module.exports.dependencies = [];
