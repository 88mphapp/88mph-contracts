const requireNoCache = require("./requireNoCache");
const config = requireNoCache("../deploy-configs/get-network-config");
const poolConfig = requireNoCache("../deploy-configs/get-pool-config");
const bprotocolConfig = requireNoCache("../deploy-configs/get-protocol-config");

const name = `${poolConfig.name}--BProtocolMarket`;

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const rewardRecipient = config.isEthereum
    ? (await get("Dumper")).address
    : config.govTreasury;

  const deployResult = await deploy(name, {
    from: deployer,
    contract: "BProtocolMarket",
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            poolConfig.moneyMarketParams.cToken,
            bprotocolConfig.comptroller,
            rewardRecipient,
            config.devWallet,
            poolConfig.stablecoin
          ]
        }
      }
    }
  });
  if (deployResult.newlyDeployed) {
    log(`${name} deployed at ${deployResult.address}`);
  }
};
module.exports.tags = [name];
module.exports.dependencies = config.isEthereum ? ["Dumper"] : [];
