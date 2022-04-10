module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const mphMinterDeployment = await get("MPHMinter");

  const deployResult = await deploy("MPHMinterLegacy", {
    from: deployer,
    contract: "MPHMinterLegacy",
    args: [mphMinterDeployment.address],
  });
  if (deployResult.newlyDeployed) {
    log(`MPHMinterLegacy deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["MPHMinterLegacy"];
module.exports.dependencies = ["MPHMinter"];
