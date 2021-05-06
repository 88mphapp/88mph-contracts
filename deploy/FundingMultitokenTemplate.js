module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("ERC20WrapperTemplate", {
    from: deployer,
    contract: "ERC20Wrapper"
  });
  if (deployResult.newlyDeployed) {
    log(`ERC20WrapperTemplate deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["ERC20WrapperTemplate"];
module.exports.dependencies = [];
