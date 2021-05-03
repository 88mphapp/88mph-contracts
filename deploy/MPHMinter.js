const config = require("../deploy-configs/get-network-config");

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const mphIssuanceModelDeployment = await get(config.mphIssuanceModel);
  const vestingDeployment = await get("Vesting");

  const deployResult = await deploy("MPHMinter", {
    from: deployer,
    args: [
      config.mph,
      config.govTreasury,
      config.devWallet,
      mphIssuanceModelDeployment.address,
      vestingDeployment.address
    ]
  });
  if (deployResult.newlyDeployed) {
    log(`MPHMinter deployed at ${deployResult.address}`);
    // Need to transfer MPHToken ownership to MPHMinter
  }
};
module.exports.tags = ["MPHMinter", "MPHRewards"];
module.exports.dependencies = [config.mphIssuanceModel, "Vesting"];
