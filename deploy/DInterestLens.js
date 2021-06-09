module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("DInterestLens", {
    from: deployer,
    contract: "DInterestLens"
  });
  if (deployResult.newlyDeployed) {
    log(`DInterestLens deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["DInterestLens"];
module.exports.dependencies = [];
