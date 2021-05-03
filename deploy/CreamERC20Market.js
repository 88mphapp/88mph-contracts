module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();
  const poolConfig = require("../deploy-configs/get-pool-config");

  const deployResult = await deploy("CreamERC20Market", {
    from: deployer,
    args: [poolConfig.moneyMarketParams.cToken, poolConfig.stablecoin]
  });
  if (deployResult.newlyDeployed) {
    log(`CreamERC20Market deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["CreamERC20Market"];
module.exports.dependencies = [];
