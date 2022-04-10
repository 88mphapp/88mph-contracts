const BigNumber = require("bignumber.js");
const requireNoCache = require("./requireNoCache");
const poolConfig = requireNoCache("../deploy-configs/get-pool-config");
const config = requireNoCache("../deploy-configs/get-network-config");

module.exports = async ({ web3, getNamedAccounts, deployments, artifacts }) => {
  const { deploy, log, get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const feeModelDeployment = await get(poolConfig.feeModel);
  const interestModelDeployment = await get(poolConfig.interestModel);
  const interestOracleName = `${poolConfig.name}--${poolConfig.interestOracle}`;
  const interestOracleDeployment = await get(interestOracleName);
  const depositNFTName = `${poolConfig.nftNamePrefix}Deposit`;
  const depositNFTDeployment = await get(depositNFTName);
  const fundingMultitokenName = `${poolConfig.nftNamePrefix}Yield Token`;
  const fundingMultitokenDeployment = await get(fundingMultitokenName);
  const mphMinterDeployment = await get("MPHMinter");

  const deployResult = await deploy(poolConfig.name, {
    from: deployer,
    contract: "DInterest",
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        init: {
          methodName: "initialize",
          args: [
            BigNumber(poolConfig.MaxDepositPeriod).toFixed(),
            BigNumber(poolConfig.MinDepositAmount).toFixed(),
            feeModelDeployment.address,
            interestModelDeployment.address,
            interestOracleDeployment.address,
            depositNFTDeployment.address,
            fundingMultitokenDeployment.address,
            mphMinterDeployment.address,
          ],
        },
      },
    },
  });
  if (deployResult.newlyDeployed) {
    log(`${poolConfig.name} deployed at ${deployResult.address}`);
  }
};
module.exports.tags = [poolConfig.name, "DInterest"];
module.exports.dependencies = [
  `${poolConfig.name}--${poolConfig.moneyMarket}`,
  poolConfig.feeModel,
  poolConfig.interestModel,
  `${poolConfig.name}--${poolConfig.interestOracle}`,
  `${poolConfig.nftNamePrefix}Deposit`,
  `${poolConfig.nftNamePrefix}Yield Token`,
  "DInterestLens",
  "MPHMinterLegacy",
];
