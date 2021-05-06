module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("EMAOracleTemplate", {
    from: deployer,
    contract: "EMAOracle"
  });
  if (deployResult.newlyDeployed) {
    log(`EMAOracleTemplate deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["EMAOracleTemplate"];
module.exports.dependencies = [];
