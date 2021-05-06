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

  const deployResult = await deploy("MPHIssuanceModel02", {
    from: deployer,
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy"
    }
  });
  if (deployResult.newlyDeployed) {
    const MPHIssuanceModel02 = artifacts.require("MPHIssuanceModel02");
    const contract = await MPHIssuanceModel02.at(deployResult.address);
    await contract.initialize(
      BigNumber(config.devRewardMultiplier).toFixed(),
      BigNumber(config.govRewardMultiplier).toFixed(),
      {
        from: deployer
      }
    );
    log(`MPHIssuanceModel02 deployed at ${deployResult.address}`);

    // transfer MPHIssuanceModel ownership to gov treasury
    await contract.transferOwnership(config.govTreasury, {
      from: deployer
    });
    log(`Transfer MPHIssuanceModel02 ownership to ${config.govTreasury}`);
  }
};
module.exports.tags = ["MPHIssuanceModel02"];
module.exports.dependencies = [];
