const config = require("../deploy-configs/get-network-config");
const poolConfig = require("../deploy-configs/get-pool-config");

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("HarvestMarket", {
    from: deployer,
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy"
    }
  });
  if (deployResult.newlyDeployed) {
    const dumperDeployment = await get("Dumper");

    const MoneyMarket = artifacts.require("HarvestMarket");
    const moneyMarketContract = await MoneyMarket.at(deployResult.address);
    await moneyMarketContract.initialize(
      poolConfig.moneyMarketParams.vault,
      dumperDeployment.address,
      poolConfig.moneyMarketParams.stakingPool,
      poolConfig.stablecoin,
      {
        from: deployer
      }
    );
    log(`HarvestMarket deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["HarvestMarket"];
module.exports.dependencies = ["Dumper"];
