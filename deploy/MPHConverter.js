module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const mphMinterDeployment = await get("MPHMinter");

  const deployResult = await deploy("MPHConverter", {
    from: deployer,
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [mphMinterDeployment.address]
        }
      }
    }
  });
  if (deployResult.newlyDeployed) {
    log(`MPHConverter deployed at ${deployResult.address}`);
  }

  // Transfer ownership to gov
  if ((await read("MPHConverter", "owner")) !== config.govTreasury) {
    await execute(
      "MPHConverter",
      { from: deployer },
      "transferOwnership",
      config.govTreasury
    );
    log(`Transfer MPHConverter ownership to ${config.govTreasury}`);
  }
};
module.exports.tags = ["MPHConverter"];
module.exports.dependencies = ["MPHMinter"];
