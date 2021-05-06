module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("NFTTemplate", {
    from: deployer,
    contract: "NFT"
  });
  if (deployResult.newlyDeployed) {
    log(`NFTTemplate deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["NFTTemplate"];
module.exports.dependencies = [];
