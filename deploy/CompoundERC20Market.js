const config = require("../deploy-configs/get-network-config");
const poolConfig = require("../deploy-configs/get-pool-config");
const compoundConfig = require("../deploy-configs/protocols/compound.json");

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy("CompoundERC20Market", {
    from: deployer,
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy"
    }
  });
  if (deployResult.newlyDeployed) {
    const dumperDeployment = await get("Dumper");

    const MoneyMarket = artifacts.require("CompoundERC20Market");
    const moneyMarketContract = await MoneyMarket.at(deployResult.address);
    await moneyMarketContract.initialize(
      poolConfig.moneyMarketParams.cToken,
      compoundConfig.comptroller,
      dumperDeployment.address,
      poolConfig.stablecoin,
      {
        from: deployer
      }
    );
    log(`CompoundERC20Market deployed at ${deployResult.address}`);
  }
};
module.exports.tags = ["CompoundERC20Market"];
module.exports.dependencies = ["Dumper"];
