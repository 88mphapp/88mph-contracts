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

  const deployResult = await deploy("xMPH", {
    from: deployer,
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy"
    }
  });
  if (deployResult.newlyDeployed) {
    const xMPH = artifacts.require("xMPH");
    const contract = await xMPH.at(deployResult.address);
    await contract.initialize(
      config.mph,
      config.xMPHRewardUnlockPeriod,
      config.govTreasury,
      {
        from: deployer
      }
    );
    log(`xMPH deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["xMPH"];
module.exports.dependencies = [];
