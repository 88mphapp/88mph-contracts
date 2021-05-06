const BigNumber = require("bignumber.js");
const config = require("../deploy-configs/get-network-config");

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("LinearDecayInterestModel", {
    from: deployer,
    args: [
      BigNumber(config.interestRateMultiplierIntercept).toFixed(),
      BigNumber(config.interestRateMultiplierSlope).toFixed()
    ]
  });
  if (deployResult.newlyDeployed) {
    log(`LinearDecayInterestModel deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["LinearDecayInterestModel"];
module.exports.dependencies = [];
