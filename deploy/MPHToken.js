const requireNoCache = require("./requireNoCache");
const config = requireNoCache("../deploy-configs/get-network-config");

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const chainId = await getChainId();
  if (chainId == 1) {
    log(`Should not deploy MPHToken on Mainnet`);
    return;
  }
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("MPHToken", {
    from: deployer
  });
  if (deployResult.newlyDeployed) {
    log(`MPHToken deployed at ${deployResult.address}`);

    const MPHToken = artifacts.require("MPHToken");
    const contract = await MPHToken.at(deployResult.address);
    await contract.initialize({
      from: deployer
    });
    log(`Initialized MPHToken`);
  }
};
module.exports.tags = ["MPHToken"];
module.exports.dependencies = [];
