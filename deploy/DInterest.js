const BigNumber = require("bignumber.js");
const poolConfig = require("../deploy-configs/get-pool-config");
const config = require("../deploy-configs/get-network-config");

module.exports = async ({
  web3,
  getNamedAccounts,
  deployments,
  getChainId,
  artifacts
}) => {
  const { deploy, log, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const moneyMarketDeployment = await get(
    `${poolConfig.name}--${poolConfig.moneyMarket}`
  );
  const feeModelDeployment = await get(poolConfig.feeModel);
  const interestModelDeployment = await get(poolConfig.interestModel);
  const interestOracleDeployment = await get(
    `${poolConfig.name}--${poolConfig.interestOracle}`
  );
  const depositNFTDeployment = await get(`${poolConfig.nftNamePrefix}Deposit`);
  const fundingMultitokenDeployment = await get(
    `${poolConfig.nftNamePrefix}Floating Rate Bond`
  );
  const mphMinterDeployment = await get("MPHMinter");

  const deployResult = await deploy(poolConfig.name, {
    from: deployer,
    contract: "DInterest",
    proxy: {
      owner: config.govTimelock,
      proxyContract: "OptimizedTransparentProxy"
    }
  });
  if (deployResult.newlyDeployed) {
    const DInterest = artifacts.require("DInterest");
    const contract = await DInterest.at(deployResult.address);
    await contract.initialize(
      BigNumber(poolConfig.MaxDepositPeriod).toFixed(),
      BigNumber(poolConfig.MinDepositAmount).toFixed(),
      poolConfig.stablecoin,
      feeModelDeployment.address,
      interestModelDeployment.address,
      interestOracleDeployment.address,
      depositNFTDeployment.address,
      fundingMultitokenDeployment.address,
      mphMinterDeployment.address,
      {
        from: deployer
      }
    );
    log(`${poolConfig.name} deployed at ${deployResult.address}`);

    // Transfer the ownership of the money market to the DInterest pool
    const MoneyMarket = artifacts.require(poolConfig.moneyMarket);
    const moneyMarketContract = await MoneyMarket.at(
      moneyMarketDeployment.address
    );
    await moneyMarketContract.transferOwnership(deployResult.address, {
      from: deployer
    });
    log(`Transferred MoneyMarket ownership to ${deployResult.address}`);

    // Transfer deposit NFT ownership to the DInterest pool
    const NFT = artifacts.require("NFT");
    const depositNFTContract = await NFT.at(depositNFTDeployment.address);
    await depositNFTContract.transferOwnership(deployResult.address, {
      from: deployer
    });
    log(`Transferred DepositNFT ownership to ${deployResult.address}`);

    // Assign funding multitoken roles
    const DEFAULT_ADMIN_ROLE = "0x00";
    const MINTER_BURNER_ROLE = web3.utils.soliditySha3("MINTER_BURNER_ROLE");
    const DIVIDEND_ROLE = web3.utils.soliditySha3("DIVIDEND_ROLE");
    const METADATA_ROLE = web3.utils.soliditySha3("METADATA_ROLE");
    const FundingMultitoken = artifacts.require("FundingMultitoken");
    const fundingMultitokenContract = await FundingMultitoken.at(
      fundingMultitokenDeployment.address
    );
    await fundingMultitokenContract.grantRole(
      MINTER_BURNER_ROLE,
      deployResult.address,
      { from: deployer }
    );
    log(
      `Grant FundingMultitoken MINTER_BURNER_ROLE to ${deployResult.address}`
    );
    await fundingMultitokenContract.grantRole(
      DIVIDEND_ROLE,
      deployResult.address,
      { from: deployer }
    );
    log(`Grant FundingMultitoken DIVIDEND_ROLE to ${deployResult.address}`);
    await fundingMultitokenContract.grantRole(
      DIVIDEND_ROLE,
      mphMinterDeployment.address,
      { from: deployer }
    );
    log(
      `Grant FundingMultitoken DIVIDEND_ROLE to ${mphMinterDeployment.address}`
    );
    await fundingMultitokenContract.grantRole(
      DIVIDEND_ROLE,
      config.govTreasury,
      { from: deployer }
    );
    log(`Grant FundingMultitoken DIVIDEND_ROLE to ${config.govTreasury}`);
    await fundingMultitokenContract.grantRole(
      METADATA_ROLE,
      config.govTreasury,
      { from: deployer }
    );
    log(`Grant FundingMultitoken METADATA_ROLE to ${config.govTreasury}`);
    await fundingMultitokenContract.renounceRole(MINTER_BURNER_ROLE, deployer, {
      from: deployer
    });
    log(`Renounce FundingMultitoken MINTER_BURNER_ROLE of ${deployer}`);
    await fundingMultitokenContract.renounceRole(DIVIDEND_ROLE, deployer, {
      from: deployer
    });
    log(`Renounce FundingMultitoken DIVIDEND_ROLE of ${deployer}`);
    await fundingMultitokenContract.renounceRole(METADATA_ROLE, deployer, {
      from: deployer
    });
    log(`Renounce FundingMultitoken METADATA_ROLE of ${deployer}`);

    // Transfer DInterest ownership to gov
    await contract.transferOwnership(config.govTreasury, {
      from: deployer
    });
    log(`Transfer ${poolConfig.name} ownership to ${config.govTreasury}`);

    const finalBalance = BigNumber(
      (await web3.eth.getBalance(deployer)).toString()
    ).div(1e18);
    log(`Deployer ETH balance: ${finalBalance.toString()} ETH`);
  }
};
module.exports.tags = [poolConfig.name, "DInterest"];
module.exports.dependencies = [
  `${poolConfig.name}--${poolConfig.moneyMarket}`,
  poolConfig.feeModel,
  poolConfig.interestModel,
  `${poolConfig.name}--${poolConfig.interestOracle}`,
  `${poolConfig.nftNamePrefix}Deposit`,
  `${poolConfig.nftNamePrefix}Floating Rate Bond`,
  "MPHRewards",
  "DInterestLens",
  "MPHMinterLegacy"
];
