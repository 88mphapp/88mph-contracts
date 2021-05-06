module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("Factory", {
    from: deployer
  });
  if (deployResult.newlyDeployed) {
    log(`Factory deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["Factory"];
module.exports.dependencies = [];
