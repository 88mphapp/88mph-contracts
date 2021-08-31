module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("NFTDescriptor", {
    from: deployer
  });
  if (deployResult.newlyDeployed) {
    log(`NFTDescriptor deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["NFTDescriptor"];
module.exports.dependencies = [];
