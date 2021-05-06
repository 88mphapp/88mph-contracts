const config = require("../deploy-configs/get-network-config");
const poolConfig = require("../deploy-configs/get-pool-config");

const name = `${poolConfig.name}--YVaultMarket`;

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployResult = await deploy(name, {
    from: deployer,
    contract: "YVaultMarket",
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy"
    }
  });
  if (deployResult.newlyDeployed) {
    const MoneyMarket = artifacts.require("YVaultMarket");
    const moneyMarketContract = await MoneyMarket.at(deployResult.address);
    await moneyMarketContract.initialize(
      poolConfig.moneyMarketParams.vault,
      config.govTreasury,
      poolConfig.stablecoin,
      {
        from: deployer
      }
    );
    log(`${name} deployed at ${deployResult.address}`);
  }
};
module.exports.tags = [name];
module.exports.dependencies = [];
