const BigNumber = require('bignumber.js')
const poolConfig = require('../deploy-configs/get-pool-config')
const config = require('../deploy-configs/get-network-config')

module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log, get } = deployments
  const { deployer } = await getNamedAccounts()

  const moneyMarketDeployment = await get(poolConfig.moneyMarket)
  const feeModelDeployment = await get(poolConfig.feeModel)
  const interestModelDeployment = await get(poolConfig.interestModel)
  const interestOracleDeployment = await get(poolConfig.interestOracle)
  const depositNFTDeployment = await get(`${poolConfig.nftNamePrefix}Deposit`)
  const fundingNFTDeployment = await get(`${poolConfig.nftNamePrefix}Bond`)
  const mphMinterDeployment = await get('MPHMinter')
  const mphIssuanceModelDeployment = await get(config.mphIssuanceModel)

  const deployResult = await deploy(poolConfig.name, {
    from: deployer,
    contract: 'DInterest',
    args: [
      {
        MinDepositPeriod: BigNumber(poolConfig.MinDepositPeriod).toFixed(),
        MaxDepositPeriod: BigNumber(poolConfig.MaxDepositPeriod).toFixed(),
        MinDepositAmount: BigNumber(poolConfig.MinDepositAmount).toFixed(),
        MaxDepositAmount: BigNumber(poolConfig.MaxDepositAmount).toFixed()
      },
      moneyMarketDeployment.address,
      poolConfig.stablecoin,
      feeModelDeployment.address,
      interestModelDeployment.address,
      interestOracleDeployment.address,
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
    await mphMinterContract.setPoolWhitelist(deployResult.address, true, { from: deployer })
    const MPHIssuanceModel = artifacts.require(config.mphIssuanceModel)
    const mphIssuanceModelContract = await MPHIssuanceModel.at(mphIssuanceModelDeployment.address)
    await mphIssuanceModelContract.setPoolDepositorRewardMintMultiplier(deployResult.address, BigNumber(poolConfig.PoolDepositorRewardMintMultiplier).toFixed(), { from: deployer })
    await mphIssuanceModelContract.setPoolDepositorRewardTakeBackMultiplier(deployResult.address, BigNumber(poolConfig.PoolDepositorRewardTakeBackMultiplier).toFixed(), { from: deployer })
    await mphIssuanceModelContract.setPoolFunderRewardMultiplier(deployResult.address, BigNumber(poolConfig.PoolFunderRewardMultiplier).toFixed(), { from: deployer })

    // Transfer the ownership of the money market to the DInterest pool
    const MoneyMarket = artifacts.require(poolConfig.moneyMarket)
    const moneyMarketContract = await MoneyMarket.at(moneyMarketDeployment.address)
    await moneyMarketContract.transferOwnership(deployResult.address, { from: deployer })

    // Transfer NFT ownerships to the DInterest pool
    const NFT = artifacts.require('NFT')
    const depositNFTContract = await NFT.at(depositNFTDeployment.address)
    const fundingNFTContract = await NFT.at(fundingNFTDeployment.address)
    await depositNFTContract.transferOwnership(deployResult.address, { from: deployer })
    await fundingNFTContract.transferOwnership(deployResult.address, { from: deployer })

    // Transfer DInterest ownership to gov
    const dInterestDeployment = await get(poolConfig.name)
    const DInterest = artifacts.require('DInterest')
    const dInterestContract = await DInterest.at(dInterestDeployment.address)
    await dInterestContract.transferOwnership(config.govTreasury, { from: deployer })
    log(`Transfer ${poolConfig.name} ownership to ${config.govTreasury}`)

    const finalBalance = BigNumber((await web3.eth.getBalance(deployer)).toString()).div(1e18)
    log(`Deployer ETH balance: ${finalBalance.toString()} ETH`)
  }
}
module.exports.tags = [poolConfig.name, 'DInterest']
module.exports.dependencies = [poolConfig.moneyMarket, poolConfig.feeModel, poolConfig.interestModel, poolConfig.interestOracle, `${poolConfig.nftNamePrefix}Deposit`, `${poolConfig.nftNamePrefix}Bond`, 'MPHRewards']
