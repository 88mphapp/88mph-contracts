const BigNumber = require("bignumber.js");

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

  const deployResult = await deploy("LinearDecayInterestModel", {
    from: deployer,
    args: [
      BigNumber(poolConfig.multiplierIntercept).toFixed(),
      BigNumber(poolConfig.multiplierSlope).toFixed()
    ]
  });
  if (deployResult.newlyDeployed) {
    log(`LinearDecayInterestModel deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["LinearDecayInterestModel"];
module.exports.dependencies = [];
