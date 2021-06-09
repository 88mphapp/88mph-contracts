module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("MPHMinterLegacy", {
    from: deployer,
    contract: "MPHMinterLegacy"
  });
  if (deployResult.newlyDeployed) {
    log(`MPHMinterLegacy deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["MPHMinterLegacy"];
module.exports.dependencies = [];
