const BigNumber = require("bignumber.js");
const poolConfig = require("../deploy-configs/get-pool-config");

const name = `${poolConfig.name}--EMAOracle`;

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { log, get, getOrNull, save } = deployments;
  const { deployer } = await getNamedAccounts();

  const moneyMarketDeployment = await get(
    `${poolConfig.name}--${poolConfig.moneyMarket}`
  );

  const FactoryDeployment = await get("Factory");
  const Factory = artifacts.require("Factory");
  const FactoryContract = await Factory.at(FactoryDeployment.address);
  const EMAOracleTemplateDeployment = await get("EMAOracleTemplate");

  const deployment = await getOrNull(name);
  if (!deployment) {
    const salt = "0x" + BigNumber(Date.now()).toString(16);
    const deployReceipt = await FactoryContract.createEMAOracle(
      EMAOracleTemplateDeployment.address,
      salt,
      BigNumber(poolConfig.EMAInitial).toFixed(),
      BigNumber(poolConfig.EMAUpdateInverval).toFixed(),
      BigNumber(poolConfig.EMASmoothingFactor).toFixed(),
      BigNumber(poolConfig.EMAAverageWindowInIntervals).toFixed(),
      moneyMarketDeployment.address,
      { from: deployer }
    );
    const txReceipt = deployReceipt.receipt;
    const address = txReceipt.logs[0].args.clone;
    const EMAOracle = artifacts.require("EMAOracle");
    const contract = await EMAOracle.at(address);
    await save(name, {
      abi: contract.abi,
      address: address,
      receipt: deployReceipt
    });
    log(`${name} deployed at ${address}`);
  }
};
module.exports.tags = [name];
module.exports.dependencies = [
  `${poolConfig.name}--${poolConfig.moneyMarket}`,
  "Factory",
  "EMAOracleTemplate"
];
