const BigNumber = require("bignumber.js");
const poolConfig = require("../deploy-configs/get-pool-config");
const config = require("../deploy-configs/get-network-config");

module.exports = async ({ web3, getNamedAccounts, deployments, artifacts }) => {
  const { log, get, execute, read } = deployments;
  const { deployer } = await getNamedAccounts();

  const moneyMarketName = `${poolConfig.name}--${poolConfig.moneyMarket}`;
  const depositNFTName = `${poolConfig.nftNamePrefix}Deposit`;
  const fundingMultitokenName = `${poolConfig.nftNamePrefix}Yield Token`;
  const mphMinterDeployment = await get("MPHMinter");
  const deployResult = await get(poolConfig.name);

  // Transfer the ownership of the money market to the DInterest pool
  if ((await read(moneyMarketName, "owner")) !== deployResult.address) {
    await execute(
      moneyMarketName,
      { from: deployer },
      "transferOwnership",
      deployResult.address
    );
    log(`Transferred MoneyMarket ownership to ${deployResult.address}`);
  }

  // Transfer deposit NFT ownership to the DInterest pool
  if ((await read(depositNFTName, "owner")) !== deployResult.address) {
    await execute(
      depositNFTName,
      { from: deployer },
      "transferOwnership",
      deployResult.address
    );
    log(`Transferred DepositNFT ownership to ${deployResult.address}`);
  }

  // Assign funding multitoken roles
  const MINTER_BURNER_ROLE = web3.utils.soliditySha3("MINTER_BURNER_ROLE");
  const DIVIDEND_ROLE = web3.utils.soliditySha3("DIVIDEND_ROLE");
  const METADATA_ROLE = web3.utils.soliditySha3("METADATA_ROLE");
  if (
    !(await read(
      fundingMultitokenName,
      "hasRole",
      MINTER_BURNER_ROLE,
      deployResult.address
    ))
  ) {
    await execute(
      fundingMultitokenName,
      { from: deployer },
      "grantRole",
      MINTER_BURNER_ROLE,
      deployResult.address
    );
    log(
      `Grant FundingMultitoken MINTER_BURNER_ROLE to ${deployResult.address}`
    );
  }
  if (
    !(await read(
      fundingMultitokenName,
      "hasRole",
      DIVIDEND_ROLE,
      deployResult.address
    ))
  ) {
    await execute(
      fundingMultitokenName,
      { from: deployer },
      "grantRole",
      DIVIDEND_ROLE,
      deployResult.address
    );
    log(`Grant FundingMultitoken DIVIDEND_ROLE to ${deployResult.address}`);
  }
  if (
    !(await read(
      fundingMultitokenName,
      "hasRole",
      DIVIDEND_ROLE,
      mphMinterDeployment.address
    ))
  ) {
    await execute(
      fundingMultitokenName,
      { from: deployer },
      "grantRole",
      DIVIDEND_ROLE,
      mphMinterDeployment.address
    );
    log(
      `Grant FundingMultitoken DIVIDEND_ROLE to ${mphMinterDeployment.address}`
    );
  }
  if (
    !(await read(
      fundingMultitokenName,
      "hasRole",
      DIVIDEND_ROLE,
      config.govTreasury
    ))
  ) {
    await execute(
      fundingMultitokenName,
      { from: deployer },
      "grantRole",
      DIVIDEND_ROLE,
      config.govTreasury
    );
    log(`Grant FundingMultitoken DIVIDEND_ROLE to ${config.govTreasury}`);
  }
  if (
    !(await read(
      fundingMultitokenName,
      "hasRole",
      METADATA_ROLE,
      config.govTreasury
    ))
  ) {
    await execute(
      fundingMultitokenName,
      { from: deployer },
      "grantRole",
      METADATA_ROLE,
      config.govTreasury
    );
    log(`Grant FundingMultitoken METADATA_ROLE to ${config.govTreasury}`);
  }

  if (
    await read(fundingMultitokenName, "hasRole", MINTER_BURNER_ROLE, deployer)
  ) {
    await execute(
      fundingMultitokenName,
      { from: deployer },
      "renounceRole",
      MINTER_BURNER_ROLE,
      deployer
    );
    log(`Renounce FundingMultitoken MINTER_BURNER_ROLE of ${deployer}`);
  }
  if (await read(fundingMultitokenName, "hasRole", DIVIDEND_ROLE, deployer)) {
    await execute(
      fundingMultitokenName,
      { from: deployer },
      "renounceRole",
      DIVIDEND_ROLE,
      deployer
    );
    log(`Renounce FundingMultitoken DIVIDEND_ROLE of ${deployer}`);
  }
  if (await read(fundingMultitokenName, "hasRole", METADATA_ROLE, deployer)) {
    await execute(
      fundingMultitokenName,
      { from: deployer },
      "renounceRole",
      METADATA_ROLE,
      deployer
    );
    log(`Renounce FundingMultitoken METADATA_ROLE of ${deployer}`);
  }

  // Transfer DInterest ownership to gov
  if ((await read(poolConfig.name, "owner")) !== config.govTreasury) {
    await execute(
      poolConfig.name,
      { from: deployer },
      "transferOwnership",
      config.govTreasury,
      true,
      false
    );
    log(`Transfer ${poolConfig.name} ownership to ${config.govTreasury}`);
  }

  const finalBalance = BigNumber(
    (await web3.eth.getBalance(deployer)).toString()
  ).div(1e18);
  log(`Deployer ETH balance: ${finalBalance.toString()} ETH`);
};
module.exports.tags = [poolConfig.name, "DInterest"];
module.exports.dependencies = [];
module.exports.runAtTheEnd = true;
