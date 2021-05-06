const poolConfig = require("../deploy-configs/get-pool-config");
const BigNumber = require("bignumber.js");

const nftName = `${poolConfig.nftNamePrefix}Deposit`;
const nftSymbol = `${poolConfig.nftSymbolPrefix}Deposit`;

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
  const NFTTemplateDeployment = await get("NFTTemplate");

  const NFTDeployment = await getOrNull(nftName);
  if (!NFTDeployment) {
    const salt = "0x" + BigNumber(Date.now()).toString(16);
    const deployReceipt = await FactoryContract.createNFT(
      NFTTemplateDeployment.address,
      salt,
      nftName,
      nftSymbol,
      { from: deployer }
    );
    const txReceipt = deployReceipt.receipt;
    const NFTAddress = txReceipt.logs[0].args.clone;
    const NFT = artifacts.require("NFT");
    const NFTContract = await NFT.at(NFTAddress);
    await save(nftName, {
      abi: NFTContract.abi,
      address: NFTAddress,
      receipt: deployReceipt
    });
    log(`${nftName} deployed at ${NFTAddress}`);
  }
};
module.exports.tags = [nftName];
module.exports.dependencies = ["Factory", "NFTTemplate"];
