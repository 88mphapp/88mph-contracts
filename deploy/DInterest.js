const BigNumber = require('bignumber.js')
const poolConfig = require('../deploy-configs/pool.json')

module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log, get } = deployments
  const { deployer } = await getNamedAccounts()

  const moneyMarketDeployment = await get(poolConfig.moneyMarket)
  const feeModelDeployment = await get(poolConfig.feeModel)
  const interestModelDeployment = await get(poolConfig.interestModel)
  const depositNFTDeployment = await get(`${poolConfig.nftNamePrefix}Deposit`)
  const fundingNFTDeployment = await get(`${poolConfig.nftNamePrefix}Funding`)
  const mphMinterDeployment = await get('MPHMinter')

  const deployResult = await deploy(poolConfig.name, {
    from: deployer,
    contract: 'DInterest',
    args: [
      BigNumber(poolConfig.MinDepositPeriod).toFixed(),
      BigNumber(poolConfig.MaxDepositPeriod).toFixed(),
      BigNumber(poolConfig.MinDepositAmount).toFixed(),
      BigNumber(poolConfig.MaxDepositAmount).toFixed(),
      moneyMarketDeployment.address,
      poolConfig.stablecoin,
      feeModelDeployment.address,
      interestModelDeployment.address,
      depositNFTDeployment.address,
      fundingNFTDeployment.address,
      mphMinterDeployment.address
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`${poolConfig.name} deployed at ${deployResult.address}`)

    // Set MPH minting multiplier for DInterest pool
    const MPHMinter = artifacts.require('MPHMinter')
    const mphMinterContract = await MPHMinter.at(mphMinterDeployment.address)
    await mphMinterContract.setPoolMintingMultiplier(deployResult.address, BigNumber(poolConfig.PoolMintingMultiplier).toFixed())
    await mphMinterContract.setPoolDepositorRewardMultiplier(deployResult.address, BigNumber(poolConfig.PoolDepositorRewardMultiplier).toFixed())
    await mphMinterContract.setPoolFunderRewardMultiplier(deployResult.address, BigNumber(poolConfig.PoolFunderRewardMultiplier).toFixed())

    // Transfer the ownership of the money market to the DInterest pool
    const MoneyMarket = artifacts.require(poolConfig.moneyMarket)
    const moneyMarketContract = await MoneyMarket.at(moneyMarketDeployment.address)
    await moneyMarketContract.transferOwnership(deployResult.address)

    // Transfer NFT ownerships to the DInterest pool
    const NFT = artifacts.require('NFT')
    const depositNFTContract = await NFT.at(depositNFTDeployment.address)
    const fundingNFTContract = await NFT.at(fundingNFTDeployment.address)
    await depositNFTContract.transferOwnership(deployResult.address)
    await fundingNFTContract.transferOwnership(deployResult.address)
  }
}
module.exports.tags = [poolConfig.name, 'DInterestPool']
module.exports.dependencies = [poolConfig.moneyMarket, poolConfig.feeModel, poolConfig.interestModel, `${poolConfig.nftNamePrefix}Deposit`, `${poolConfig.nftNamePrefix}Funding`, 'MPHRewards']
