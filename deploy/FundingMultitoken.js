const config = require("../deploy-configs/get-network-config");
const poolConfig = require("../deploy-configs/get-pool-config");
const BigNumber = require("bignumber.js");

const metadataURI = "";
const name = `${poolConfig.nftNamePrefix}Floating Rate Bond`;
const baseName = `${poolConfig.nftNamePrefix}Floating Rate Bond `;
const baseSymbol = `${poolConfig.nftSymbolPrefix}Floating-Rate-Bond-`;

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { log, get, getOrNull, save } = deployments;
  const { deployer } = await getNamedAccounts();

  const FactoryDeployment = await get("Factory");
  const Factory = artifacts.require("Factory");
  const FactoryContract = await Factory.at(FactoryDeployment.address);
  const templateDeployment = await get("FundingMultitokenTemplate");
  const erc20WrapperTemplateDeployment = await get("ERC20WrapperTemplate");

  const deployment = await getOrNull(name);
  if (!deployment) {
    const dividendTokens = [poolConfig.stablecoin, config.mph];
    const ERC20 = artifacts.require("ERC20");
    const stablecoinContract = await ERC20.at(poolConfig.stablecoin);
    const stablecoinDecimals = await stablecoinContract.decimals();
    const salt = "0x" + BigNumber(Date.now()).toString(16);
    const deployReceipt = await FactoryContract.createFundingMultitoken(
      templateDeployment.address,
      salt,
      metadataURI,
      dividendTokens,
      erc20WrapperTemplateDeployment.address,
      true,
      baseName,
      baseSymbol,
      stablecoinDecimals,
      { from: deployer }
    );
    const txReceipt = deployReceipt.receipt;
    const address = txReceipt.logs[0].args.clone;
    const FundingMultitoken = artifacts.require("FundingMultitoken");
    const contract = await FundingMultitoken.at(address);
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
  "Factory",
  "FundingMultitokenTemplate",
  "ERC20WrapperTemplate"
];
