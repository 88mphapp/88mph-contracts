const config = require("../deploy-configs/get-network-config");
const poolConfig = require("../deploy-configs/get-pool-config");
const aaveConfig = require("../deploy-configs/protocols/aave.json");

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("AaveMarket", {
    from: deployer,
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy"
    }
  });
  if (deployResult.newlyDeployed) {
    const dumperDeployment = await get("Dumper");

    const MoneyMarket = artifacts.require("AaveMarket");
    const moneyMarketContract = await MoneyMarket.at(deployResult.address);
    await moneyMarketContract.initialize(
      aaveConfig.lendingPoolAddressesProvider,
      poolConfig.moneyMarketParams.aToken,
      aaveConfig.aaveMining,
      dumperDeployment.address,
      poolConfig.stablecoin,
      {
        from: deployer
      }
    );
    log(`AaveMarket deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["AaveMarket"];
module.exports.dependencies = ["Dumper"];
