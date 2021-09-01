const config = require("../deploy-configs/get-network-config");
const poolConfig = require("../deploy-configs/get-pool-config");

const name = `${poolConfig.name}--HarvestMarket`;

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const dumperDeployment = await get("Dumper");

  const deployResult = await deploy(name, {
    from: deployer,
    contract: "HarvestMarket",
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            poolConfig.moneyMarketParams.vault,
            dumperDeployment.address,
            poolConfig.moneyMarketParams.stakingPool,
            config.govTreasury,
            poolConfig.stablecoin
          ]
        }
      }
    }
  });
  if (deployResult.newlyDeployed) {
    log(`${name} deployed at ${deployResult.address}`);
  }
};
module.exports.tags = [name];
module.exports.dependencies = ["Dumper"];
