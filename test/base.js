// Libraries
const BigNumber = require('bignumber.js')
const { assert } = require('hardhat')

// Contract artifacts
const DInterest = module.exports.DInterest = artifacts.require('DInterest')
const PercentageFeeModel = module.exports.PercentageFeeModel = artifacts.require('PercentageFeeModel')
const LinearDecayInterestModel = module.exports.LinearDecayInterestModel = artifacts.require('LinearDecayInterestModel')
const NFT = module.exports.NFT = artifacts.require('NFT')
const FundingMultitoken = module.exports.FundingMultitoken = artifacts.require('FundingMultitoken')
const Factory = module.exports.Factory = artifacts.require('Factory')
const MPHToken = module.exports.MPHToken = artifacts.require('MPHToken')
const MPHMinter = module.exports.MPHMinter = artifacts.require('MPHMinter')
const ERC20Mock = module.exports.ERC20Mock = artifacts.require('ERC20Mock')
const EMAOracle = module.exports.EMAOracle = artifacts.require('EMAOracle')
const MPHIssuanceModel = module.exports.MPHIssuanceModel = artifacts.require('MPHIssuanceModel02')
const Vesting = module.exports.Vesting = artifacts.require('Vesting')
const Vesting02 = module.exports.Vesting02 = artifacts.require('Vesting02')

// Constants
const PRECISION = module.exports.PRECISION = 1e18
const STABLECOIN_PRECISION = module.exports.STABLECOIN_PRECISION = 1e6
const YEAR_IN_SEC = module.exports.YEAR_IN_SEC = 31556952 // Number of seconds in a year
const multiplierIntercept = module.exports.multiplierIntercept = 0.5 * PRECISION
const multiplierSlope = module.exports.multiplierSlope = 0.25 / YEAR_IN_SEC * PRECISION
const MaxDepositPeriod = module.exports.MaxDepositPeriod = 3 * YEAR_IN_SEC // 3 years in seconds
const MinDepositAmount = module.exports.MinDepositAmount = BigNumber(0.1 * STABLECOIN_PRECISION).toFixed() // 0.1 stablecoin
const PoolDepositorRewardMintMultiplier = module.exports.PoolDepositorRewardMintMultiplier = BigNumber(3.168873e-13 * PRECISION * (PRECISION / STABLECOIN_PRECISION)).toFixed() // 1e5 stablecoin * 1 year => 1 MPH
const PoolFunderRewardMultiplier = module.exports.PoolFunderRewardMultiplier = BigNumber(3.168873e-13 * PRECISION * (PRECISION / STABLECOIN_PRECISION)).toFixed() // 1e5 stablecoin * 1 year => 1 MPH
const DevRewardMultiplier = module.exports.DevRewardMultiplier = BigNumber(0.1 * PRECISION).toFixed()
const GovRewardMultiplier = module.exports.GovRewardMultiplier = BigNumber(0.1 * PRECISION).toFixed()
const EMAUpdateInterval = module.exports.EMAUpdateInterval = 24 * 60 * 60
const EMASmoothingFactor = module.exports.EMASmoothingFactor = BigNumber(2 * PRECISION).toFixed()
const EMAAverageWindowInIntervals = module.exports.EMAAverageWindowInIntervals = 30
const PoolFunderRewardVestPeriod = module.exports.PoolFunderRewardVestPeriod = 0 * 24 * 60 * 60 // 0 days
const MINTER_BURNER_ROLE = module.exports.MINTER_BURNER_ROLE = web3.utils.soliditySha3('MINTER_BURNER_ROLE')
const DIVIDEND_ROLE = module.exports.DIVIDEND_ROLE = web3.utils.soliditySha3('DIVIDEND_ROLE')
const WHITELISTER_ROLE = module.exports.WHITELISTER_ROLE = web3.utils.soliditySha3('WHITELISTER_ROLE')
const WHITELISTED_POOL_ROLE = module.exports.WHITELISTED_POOL_ROLE = web3.utils.soliditySha3('WHITELISTED_POOL_ROLE')

const epsilon = module.exports.epsilon = 1e-4
const INF = module.exports.INF = BigNumber(2).pow(256).minus(1).toFixed()
const ZERO_ADDR = module.exports.ZERO_ADDR = '0x0000000000000000000000000000000000000000'
const DEFAULT_SALT = module.exports.DEFAULT_SALT = '0x0000000000000000000000000000000000000000000000000000000000000000'

// Utilities
// travel `time` seconds forward in time
const timeTravel = module.exports.timeTravel = (time) => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send({
      jsonrpc: '2.0',
      method: 'evm_increaseTime',
      params: [time],
      id: new Date().getTime()
    }, (err, result) => {
      if (err) { return reject(err) }
      return resolve(result)
    })
  })
}

const latestBlockTimestamp = module.exports.latestBlockTimestamp = async () => {
  return (await web3.eth.getBlock('latest')).timestamp
}

const calcFeeAmount = module.exports.calcFeeAmount = (interestAmount) => {
  return interestAmount.times(0.2)
}

const applyFee = module.exports.applyFee = (interestAmount) => {
  return interestAmount.minus(calcFeeAmount(interestAmount))
}

const getIRMultiplier = module.exports.getIRMultiplier = (depositPeriodInSeconds) => {
  const multiplierDecrease = BigNumber(depositPeriodInSeconds).times(multiplierSlope)
  if (multiplierDecrease.gte(multiplierIntercept)) {
    return 0
  } else {
    return BigNumber(multiplierIntercept).minus(multiplierDecrease).div(PRECISION).toNumber()
  }
}

const calcInterestAmount = module.exports.calcInterestAmount = (depositAmount, interestRatePerSecond, depositPeriodInSeconds, applyFee) => {
  const IRMultiplier = getIRMultiplier(depositPeriodInSeconds)
  const interestBeforeFee = BigNumber(depositAmount).times(depositPeriodInSeconds).times(interestRatePerSecond).times(IRMultiplier)
  return applyFee ? interestBeforeFee.minus(calcFeeAmount(interestBeforeFee)) : interestBeforeFee
}

// Converts a JS number into a string that doesn't use scientific notation
const num2str = module.exports.num2str = (num) => {
  return BigNumber(num).integerValue().toFixed()
}

const epsilonEq = module.exports.epsilonEq = (curr, prev, ep) => {
  const _epsilon = ep || epsilon
  return BigNumber(curr).eq(prev) ||
    (!BigNumber(prev).isZero() && BigNumber(curr).minus(prev).div(prev).abs().lt(_epsilon)) ||
    (!BigNumber(curr).isZero() && BigNumber(prev).minus(curr).div(curr).abs().lt(_epsilon))
}

const assertEpsilonEq = module.exports.assertEpsilonEq = (a, b, message) => {
  assert(epsilonEq(a, b), `assertEpsilonEq error, a=${BigNumber(a).toString()}, b=${BigNumber(b).toString()}, message=${message}`)
}

const factoryReceiptToContract = module.exports.factoryReceiptToContract = async (receipt, contractArtifact) => {
  return await contractArtifact.at(receipt.logs[receipt.logs.length - 1].args.clone)
}

const aaveMoneyMarketModule = () => {
  let aToken
  let lendingPool
  let lendingPoolAddressesProvider

  const deployMoneyMarket = async (accounts, factory, stablecoin, rewards) => {
    // Contract artifacts
    const AaveMarket = artifacts.require('AaveMarket')
    const ATokenMock = artifacts.require('ATokenMock')
    const LendingPoolMock = artifacts.require('LendingPoolMock')
    const LendingPoolAddressesProviderMock = artifacts.require('LendingPoolAddressesProviderMock')

    // Initialize mock Aave contracts
    aToken = await ATokenMock.new(stablecoin.address)
    lendingPool = await LendingPoolMock.new()
    await lendingPool.setReserveAToken(stablecoin.address, aToken.address)
    lendingPoolAddressesProvider = await LendingPoolAddressesProviderMock.new()
    await lendingPoolAddressesProvider.setLendingPoolImpl(lendingPool.address)

    // Mint stablecoins
    const mintAmount = 1000 * STABLECOIN_PRECISION
    await stablecoin.mint(lendingPool.address, num2str(mintAmount))

    // Initialize the money market
    const marketTemplate = await AaveMarket.new()
    const marketReceipt = await factory.createAaveMarket(marketTemplate.address, DEFAULT_SALT, lendingPoolAddressesProvider.address, aToken.address, stablecoin.address)
    return await factoryReceiptToContract(marketReceipt, AaveMarket)
  }

  const timePass = async (timeInYears) => {
    await timeTravel(timeInYears * YEAR_IN_SEC)
    await aToken.mintInterest(num2str(timeInYears * YEAR_IN_SEC))
  }

  return {
    deployMoneyMarket,
    timePass
  }
}

const compoundERC20MoneyMarketModule = () => {
  let cToken
  let comptroller
  let comp
  const INIT_INTEREST_RATE = 0.1 // 10% APY

  const deployMoneyMarket = async (accounts, factory, stablecoin, rewards) => {
    // Contract artifacts
    const CompoundERC20Market = artifacts.require('CompoundERC20Market')
    const CERC20Mock = artifacts.require('CERC20Mock')
    const ComptrollerMock = artifacts.require('ComptrollerMock')

    // Deploy Compound mock contracts
    cToken = await CERC20Mock.new(stablecoin.address)
    comp = await ERC20Mock.new()
    comptroller = await ComptrollerMock.new(comp.address)

    // Mint stablecoins
    const mintAmount = 1000 * STABLECOIN_PRECISION
    await stablecoin.mint(cToken.address, num2str(mintAmount))

    // Initialize the money market
    const marketTemplate = await CompoundERC20Market.new()
    const marketReceipt = await factory.createCompoundERC20Market(marketTemplate.address, DEFAULT_SALT, cToken.address, comptroller.address, rewards, stablecoin.address)
    return await factoryReceiptToContract(marketReceipt, CompoundERC20Market)
  }

  const timePass = async (timeInYears) => {
    await timeTravel(timeInYears * YEAR_IN_SEC)
    const currentExRate = BigNumber(await cToken.exchangeRateStored())
    const rateAfterTimePasses = BigNumber(currentExRate).times(1 + timeInYears * INIT_INTEREST_RATE)
    await cToken._setExchangeRateStored(num2str(rateAfterTimePasses))
  }

  return {
    deployMoneyMarket,
    timePass
  }
}

const creamERC20MoneyMarketModule = () => {
  let cToken
  const INIT_INTEREST_RATE = 0.1 // 10% APY

  const deployMoneyMarket = async (accounts, factory, stablecoin, rewards) => {
    // Contract artifacts
    const CreamERC20Market = artifacts.require('CreamERC20Market')
    const CERC20Mock = artifacts.require('CERC20Mock')

    // Deploy Compound mock contracts
    cToken = await CERC20Mock.new(stablecoin.address)

    // Mint stablecoins
    const mintAmount = 1000 * STABLECOIN_PRECISION
    await stablecoin.mint(cToken.address, num2str(mintAmount))

    // Initialize the money market
    const marketTemplate = await CreamERC20Market.new()
    const marketReceipt = await factory.createCreamERC20Market(marketTemplate.address, DEFAULT_SALT, cToken.address, stablecoin.address)
    return await factoryReceiptToContract(marketReceipt, CreamERC20Market)
  }

  const timePass = async (timeInYears) => {
    await timeTravel(timeInYears * YEAR_IN_SEC)
    const currentExRate = BigNumber(await cToken.exchangeRateStored())
    const rateAfterTimePasses = BigNumber(currentExRate).times(1 + timeInYears * INIT_INTEREST_RATE)
    await cToken._setExchangeRateStored(num2str(rateAfterTimePasses))
  }

  return {
    deployMoneyMarket,
    timePass
  }
}

const harvestMoneyMarketModule = () => {
  let vault
  let stablecoin
  const INIT_INTEREST_RATE = 0.1 // 10% APY

  const deployMoneyMarket = async (accounts, factory, _stablecoin, rewards) => {
    // Contract artifacts
    const VaultMock = artifacts.require('VaultMock')
    const HarvestStakingMock = artifacts.require('HarvestStakingMock')
    const HarvestMarket = artifacts.require('HarvestMarket')

    // Deploy mock contracts
    stablecoin = _stablecoin
    vault = await VaultMock.new(stablecoin.address)

    // Initialize FARM rewards
    const farmToken = await ERC20Mock.new()
    const farmRewards = 1000 * STABLECOIN_PRECISION
    const harvestStaking = await HarvestStakingMock.new(vault.address, farmToken.address, Math.floor(Date.now() / 1e3 - 60))
    await farmToken.mint(harvestStaking.address, num2str(farmRewards))
    await harvestStaking.setRewardDistribution(accounts[0], true)
    await harvestStaking.notifyRewardAmount(num2str(farmRewards), { from: accounts[0] })

    // Initialize the money market
    const marketTemplate = await HarvestMarket.new()
    const marketReceipt = await factory.createHarvestMarket(marketTemplate.address, DEFAULT_SALT, vault.address, rewards, harvestStaking.address, stablecoin.address)
    return await factoryReceiptToContract(marketReceipt, HarvestMarket)
  }

  const timePass = async (timeInYears) => {
    await timeTravel(timeInYears * YEAR_IN_SEC)
    await stablecoin.mint(vault.address, num2str(BigNumber(await stablecoin.balanceOf(vault.address)).times(INIT_INTEREST_RATE).times(timeInYears)))
  }

  return {
    deployMoneyMarket,
    timePass
  }
}

const yvaultMoneyMarketModule = () => {
  let vault
  let stablecoin
  const INIT_INTEREST_RATE = 0.1 // 10% APY

  const deployMoneyMarket = async (accounts, factory, _stablecoin, rewards) => {
    // Contract artifacts
    const VaultMock = artifacts.require('VaultMock')
    const YVaultMarket = artifacts.require('YVaultMarket')

    // Deploy mock contracts
    stablecoin = _stablecoin
    vault = await VaultMock.new(stablecoin.address)

    // Initialize the money market
    const marketTemplate = await YVaultMarket.new()
    const marketReceipt = await factory.createYVaultMarket(marketTemplate.address, DEFAULT_SALT, vault.address, stablecoin.address)
    return await factoryReceiptToContract(marketReceipt, YVaultMarket)
  }

  const timePass = async (timeInYears) => {
    await timeTravel(timeInYears * YEAR_IN_SEC)
    await stablecoin.mint(vault.address, num2str(BigNumber(await stablecoin.balanceOf(vault.address)).times(INIT_INTEREST_RATE).times(timeInYears)))
  }

  return {
    deployMoneyMarket,
    timePass
  }
}

const moneyMarketModuleList = module.exports.moneyMarketModuleList = [
  /*{
    name: 'Aave',
    moduleGenerator: aaveMoneyMarketModule
  },
  {
    name: 'CompoundERC20',
    moduleGenerator: compoundERC20MoneyMarketModule
  },
  {
    name: 'CreamERC20',
    moduleGenerator: creamERC20MoneyMarketModule
  },
  {
    name: 'Harvest',
    moduleGenerator: harvestMoneyMarketModule
  },*/
  {
    name: 'YVault',
    moduleGenerator: yvaultMoneyMarketModule
  }
]
