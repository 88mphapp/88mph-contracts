const config = require("../deploy-configs/get-network-config");

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const chainId = await getChainId();
  if (chainId == 1) {
    log(`Should not deploy Vesting on Mainnet`);
    return;
  }
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("Vesting", {
    from: deployer,
    args: [config.mph]
  });
  if (deployResult.newlyDeployed) {
    log(`Vesting deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["Vesting"];
module.exports.dependencies = [];
