module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("FundingMultitokenTemplate", {
    from: deployer,
    contract: "FundingMultitoken"
  });
  if (deployResult.newlyDeployed) {
    log(`FundingMultitokenTemplate deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["FundingMultitokenTemplate"];
module.exports.dependencies = [];
