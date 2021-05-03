const BigNumber = require("bignumber.js");
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

  const moneyMarketDeployment = await get(poolConfig.moneyMarket);

  const deployResult = await deploy("EMAOracle", {
    from: deployer,
    contract: "EMAOracle",
    args: [
      BigNumber(poolConfig.EMAInitial).toFixed(),
      BigNumber(poolConfig.EMAUpdateInverval).toFixed(),
      BigNumber(poolConfig.EMASmoothingFactor).toFixed(),
      BigNumber(poolConfig.EMAAverageWindowInIntervals).toFixed(),
      moneyMarketDeployment.address
    ]
  });
  if (deployResult.newlyDeployed) {
    log(`EMAOracle deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["EMAOracle"];
module.exports.dependencies = [poolConfig.moneyMarket];
