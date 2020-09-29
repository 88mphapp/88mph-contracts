const env = require('@nomiclabs/buidler')
const BigNumber = require('bignumber.js')

async function main () {
  const AaveMarket = env.artifacts.require('AaveMarket')
  const providerAddress = '0x24a42fD28C976A61Df5D00D0599C34c4f90748c8' // LendingPoolAddressesProvider Mainnet
  const stablecoinAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F' // DAI Mainnet
  const market = await AaveMarket.new(providerAddress, stablecoinAddress)
  console.log(`Deployed AaveMarket at address ${market.address}`)

  const FeeModel = env.artifacts.require('FeeModel')
  const feeModel = await FeeModel.new()
  console.log(`Deployed FeeModel at address ${feeModel.address}`)

  const NFT = env.artifacts.require('NFT')
  const depositNFT = await NFT.new('88mph Aave-Pool Deposit', '88mph-Aave-Deposit')
  console.log(`Deployed depositNFT at address ${depositNFT.address}`)
  const fundingNFT = await NFT.new('88mph Aave-Pool Long Position', '88mph-Aave-Long')
  console.log(`Deployed fundingNFT at address ${fundingNFT.address}`)

  const DInterest = env.artifacts.require('DInterest')
  const UIRMultiplier = BigNumber(0.75 * 1e18).integerValue().toFixed() // Minimum safe avg interest rate multiplier
  const MinDepositPeriod = 90 * 24 * 60 * 60 // 90 days in seconds
  const MaxDepositAmount = BigNumber(10000 * 1e18).toFixed() // 10000 stablecoins
  const dInterestPool = await DInterest.new(UIRMultiplier, MinDepositPeriod, MaxDepositAmount, market.address, stablecoinAddress, feeModel.address, depositNFT.address, fundingNFT.address)
  console.log(`Deployed DInterest at address ${dInterestPool.address}`)

  await market.transferOwnership(dInterestPool.address)
  console.log(`Transferred AaveMarket's ownership to ${dInterestPool.address}`)

  await depositNFT.transferOwnership(dInterestPool.address)
  console.log(`Transferred depositNFT's ownership to ${dInterestPool.address}`)

  await fundingNFT.transferOwnership(dInterestPool.address)
  console.log(`Transferred fundingNFT's ownership to ${dInterestPool.address}`)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
