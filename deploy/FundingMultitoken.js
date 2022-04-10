const requireNoCache = require("./requireNoCache");
const config = requireNoCache("../deploy-configs/get-network-config");
const poolConfig = requireNoCache("../deploy-configs/get-pool-config");
const BigNumber = require("bignumber.js");

const name = `${poolConfig.nftNamePrefix}Yield Token`;
const baseName = `${poolConfig.nftNamePrefix}Yield Token `;
const baseSymbol = `${poolConfig.nftSymbolPrefix}Yield-Token-`;

module.exports = async ({ getNamedAccounts, deployments, artifacts }) => {
  const { log, get, deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const mphAddress = config.isEthereum
    ? config.mph
    : (await get("MPHToken")).address;
  const dividendTokens = [poolConfig.stablecoin, mphAddress];
  const ERC20 = artifacts.require("ERC20");
  const stablecoinContract = await ERC20.at(poolConfig.stablecoin);
  const stablecoinDecimals = await stablecoinContract.decimals.call();
  const erc20WrapperTemplateDeployment = await get("ERC20WrapperTemplate");

  const deployResult = await deploy(name, {
    from: deployer,
    contract: "FundingMultitoken",
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            deployer,
            poolConfig.fundingMultitokenMetadataURI,
            dividendTokens,
            erc20WrapperTemplateDeployment.address,
            true,
            baseName,
            baseSymbol,
            BigNumber(stablecoinDecimals).toString(),
          ],
        },
      },
    },
  });

  if (deployResult.newlyDeployed) {
    log(`${name} deployed at ${deployResult.address}`);
  }
};
module.exports.tags = [name, "FundingMultitoken"];
module.exports.dependencies = config.isEthereum
  ? ["ERC20WrapperTemplate"]
  : ["ERC20WrapperTemplate", "MPHToken"];
