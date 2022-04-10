const requireNoCache = require("./requireNoCache");
const config = requireNoCache("../deploy-configs/get-network-config");
const poolConfig = requireNoCache("../deploy-configs/get-pool-config");
const aaveConfig = requireNoCache("../deploy-configs/get-protocol-config");

const name = `${poolConfig.name}--AaveMarket`;

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const rewardRecipient = config.isEthereum
    ? (await get("Dumper")).address
    : config.govTreasury;

  const deployResult = await deploy(name, {
    from: deployer,
    contract: "AaveMarket",
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            aaveConfig.lendingPoolAddressesProvider,
            poolConfig.moneyMarketParams.aToken,
            aaveConfig.aaveMining,
            rewardRecipient,
            config.govTreasury,
            poolConfig.stablecoin,
          ],
        },
      },
    },
  });
  if (deployResult.newlyDeployed) {
    log(`${name} deployed at ${deployResult.address}`);
  }
};
module.exports.tags = [name];
module.exports.dependencies = config.isEthereum ? ["Dumper"] : [];
