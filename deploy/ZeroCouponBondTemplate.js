module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("ZeroCouponBondTemplate", {
    from: deployer,
    contract: "ZeroCouponBond"
  });
  if (deployResult.newlyDeployed) {
    log(`ZeroCouponBondTemplate deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["ZeroCouponBondTemplate"];
module.exports.dependencies = [];
