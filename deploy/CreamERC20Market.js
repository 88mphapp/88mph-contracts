const config = require("../deploy-configs/get-network-config");
const poolConfig = require("../deploy-configs/get-pool-config");

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("CreamERC20Market", {
    from: deployer,
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy"
    }
  });
  if (deployResult.newlyDeployed) {
    const MoneyMarket = artifacts.require("CreamERC20Market");
    const moneyMarketContract = await MoneyMarket.at(deployResult.address);
    await moneyMarketContract.initialize(
      poolConfig.moneyMarketParams.cToken,
      poolConfig.stablecoin,
      {
        from: deployer
      }
    );
    log(`CreamERC20Market deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["CreamERC20Market"];
module.exports.dependencies = [];
