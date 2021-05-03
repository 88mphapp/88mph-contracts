module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();
  const poolConfig = require("../deploy-configs/get-pool-config");

  const dumperDeployment = await get("Dumper");

  const deployResult = await deploy("HarvestMarket", {
    from: deployer,
    args: [
      poolConfig.moneyMarketParams.vault,
      dumperDeployment.address,
      poolConfig.moneyMarketParams.stakingPool,
      poolConfig.stablecoin
    ]
  });
  if (deployResult.newlyDeployed) {
    log(`HarvestMarket deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["HarvestMarket"];
module.exports.dependencies = ["Dumper"];
