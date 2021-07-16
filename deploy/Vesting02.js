const config = require("../deploy-configs/get-network-config");

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("Vesting02", {
    from: deployer,
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy"
    }
  });
  if (deployResult.newlyDeployed) {
    const Vesting02 = artifacts.require("Vesting02");
    const contract = await Vesting02.at(deployResult.address);
    await contract.initialize(config.mph, "Vested MPH", "veMPH", {
      from: deployer
    });
    log(`Vesting02 deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["Vesting02"];
module.exports.dependencies = [];
