const hre = require("hardhat");
const fs = require("fs");
const { accessSync, constants } = fs;
const requireNoCache = require("../deploy/requireNoCache");

// global config
const startBlockNumber = 19889933; // block number for starting to keep track of the contracts
const network = "matic";

async function main() {
  const configList = require("./output-subgraph-configs.json");

  let allSubgraphConfigs = "";
  let allPoolAddresses = "";
  let allPoolDecimals = "";
  let allPoolDeployBlocks = "";
  for (let config of configList) {
    const poolConfig = requireNoCache(
      `../deploy-configs/pools/${config.network}/${config.pool}.json`
    );
    const poolName = poolConfig.name;
    const deployment = requireNoCache(
      `../deployments/${config.network}/${poolName}.json`
    );

    // generate configs
    const subgraphConfig = `  - kind: ethereum/contract
    name: ${config.pool}
    network: ${network}
    source:
      address: "${deployment.address}"
      abi: DInterest
      startBlock: ${startBlockNumber}
    mapping:
      kind: ethereum/events
      apiVersion: 0.0.4
      language: wasm/assemblyscript
      entities:
        - DPoolList
        - DPool
        - User
        - Deposit
        - Funder
        - Funding
        - UserTotalDeposit
        - FunderTotalInterest
      abis:
        - name: DInterest
          file: ./abis/DInterest.json
        - name: IInterestOracle
          file: ./abis/IInterestOracle.json
        - name: ERC20
          file: ./abis/ERC20.json
        - name: FundingMultitoken
          file: ./abis/FundingMultitoken.json
        - name: MoneyMarket
          file: ./abis/MoneyMarket.json
      eventHandlers:
        - event: EDeposit(indexed address,indexed uint256,uint256,uint256,uint256,uint64)
          handler: handleEDeposit
        - event: ETopupDeposit(indexed address,indexed uint64,uint256,uint256,uint256)
          handler: handleETopupDeposit
        - event: EWithdraw(indexed address,indexed uint256,indexed bool,uint256,uint256)
          handler: handleEWithdraw
        - event: EPayFundingInterest(indexed uint256,uint256,uint256)
          handler: handleEPayFundingInterest
        - event: EFund(indexed address,indexed uint64,uint256,uint256)
          handler: handleEFund
        - event: ESetParamAddress(indexed address,indexed string,address)
          handler: handleESetParamAddress
        - event: ESetParamUint(indexed address,indexed string,uint256)
          handler: handleESetParamUint
      blockHandlers:
        - handler: handleBlock
      file: ./src/DInterest.ts\n`;
    const poolAddress = `POOL_ADDRESSES.push("${deployment.address.toLowerCase()}"); // ${
      config.pool
    }\n`;
    const poolDecimals = `POOL_STABLECOIN_DECIMALS.push(${config.decimals}); // ${config.pool}\n`;
    const poolDeployBlock = `POOL_DEPLOY_BLOCKS.push(${startBlockNumber}); // ${config.pool}\n`;

    // append configs
    allSubgraphConfigs += subgraphConfig;
    allPoolAddresses += poolAddress;
    allPoolDecimals += poolDecimals;
    allPoolDeployBlocks += poolDeployBlock;
  }

  // log output
  console.log(allSubgraphConfigs);
  console.log(allPoolAddresses);
  console.log(allPoolDecimals);
  console.log(allPoolDeployBlocks);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
