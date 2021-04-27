// Libraries
const BigNumber = require('bignumber.js')
const { assert } = require('hardhat')

// Contract artifacts
const DInterest = artifacts.require('DInterest')
const PercentageFeeModel = artifacts.require('PercentageFeeModel')
const LinearDecayInterestModel = artifacts.require('LinearDecayInterestModel')
const NFT = artifacts.require('NFT')
const FundingMultitoken = artifacts.require('FundingMultitoken')
const Factory = artifacts.require('Factory')
const MPHToken = artifacts.require('MPHToken')
const MPHMinter = artifacts.require('MPHMinter')
const ERC20Mock = artifacts.require('ERC20Mock')
const EMAOracle = artifacts.require('EMAOracle')
const MPHIssuanceModel = artifacts.require('MPHIssuanceModel02')
const Vesting = artifacts.require('Vesting')
const Vesting02 = artifacts.require('Vesting02')

const ZeroCouponBond = artifacts.require('ZeroCouponBond')

// Constants
const PRECISION = 1e18
const STABLECOIN_PRECISION = 1e6
const YEAR_IN_SEC = 31556952 // Number of seconds in a year
const multiplierIntercept = 0.5 * PRECISION
const multiplierSlope = 0.25 / YEAR_IN_SEC * PRECISION
const MaxDepositPeriod = 3 * YEAR_IN_SEC // 3 years in seconds
const MinDepositAmount = BigNumber(0.1 * STABLECOIN_PRECISION).toFixed() // 0.1 stablecoin
const PoolDepositorRewardMintMultiplier = BigNumber(3.168873e-13 * PRECISION * (PRECISION / STABLECOIN_PRECISION)).toFixed() // 1e5 stablecoin * 1 year => 1 MPH
const PoolFunderRewardMultiplier = BigNumber(3.168873e-13 * PRECISION * (PRECISION / STABLECOIN_PRECISION)).toFixed() // 1e5 stablecoin * 1 year => 1 MPH
const DevRewardMultiplier = BigNumber(0.1 * PRECISION).toFixed()
const GovRewardMultiplier = BigNumber(0.1 * PRECISION).toFixed()
const EMAUpdateInterval = 24 * 60 * 60
const EMASmoothingFactor = BigNumber(2 * PRECISION).toFixed()
const EMAAverageWindowInIntervals = 30
const PoolFunderRewardVestPeriod = 0 * 24 * 60 * 60 // 0 days
const MINTER_BURNER_ROLE = web3.utils.soliditySha3('MINTER_BURNER_ROLE')
const DIVIDEND_ROLE = web3.utils.soliditySha3('DIVIDEND_ROLE')
const WHITELISTER_ROLE = web3.utils.soliditySha3('WHITELISTER_ROLE')
const WHITELISTED_POOL_ROLE = web3.utils.soliditySha3('WHITELISTED_POOL_ROLE')

const epsilon = 1e-4
const INF = BigNumber(2).pow(256).minus(1).toFixed()
const ZERO_ADDR = '0x0000000000000000000000000000000000000000'
const DEFAULT_SALT = '0x0000000000000000000000000000000000000000000000000000000000000000'

// Utilities
// travel `time` seconds forward in time
function timeTravel (time) {
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

async function latestBlockTimestamp () {
  return (await web3.eth.getBlock('latest')).timestamp
}

function calcFeeAmount (interestAmount) {
  return interestAmount.times(0.2)
}

function applyFee (interestAmount) {
  return interestAmount.minus(calcFeeAmount(interestAmount))
}

function getIRMultiplier (depositPeriodInSeconds) {
  const multiplierDecrease = BigNumber(depositPeriodInSeconds).times(multiplierSlope)
  if (multiplierDecrease.gte(multiplierIntercept)) {
    return 0
  } else {
    return BigNumber(multiplierIntercept).minus(multiplierDecrease).div(PRECISION).toNumber()
  }
}

function calcInterestAmount (depositAmount, interestRatePerSecond, depositPeriodInSeconds, shouldApplyFee) {
  const IRMultiplier = getIRMultiplier(depositPeriodInSeconds)
  const interestBeforeFee = BigNumber(depositAmount).times(depositPeriodInSeconds).times(interestRatePerSecond).times(IRMultiplier)
  return shouldApplyFee ? applyFee(interestBeforeFee) : interestBeforeFee
}

// Converts a JS number into a string that doesn't use scientific notation
function num2str (num) {
  return BigNumber(num).integerValue().toFixed()
}

function epsilonEq (curr, prev, ep) {
  const _epsilon = ep || epsilon
  return BigNumber(curr).eq(prev) ||
    (!BigNumber(prev).isZero() && BigNumber(curr).minus(prev).div(prev).abs().lt(_epsilon)) ||
    (!BigNumber(curr).isZero() && BigNumber(prev).minus(curr).div(curr).abs().lt(_epsilon))
}

function assertEpsilonEq (a, b, message) {
  assert(epsilonEq(a, b), `assertEpsilonEq error, a=${BigNumber(a).toString()}, b=${BigNumber(b).toString()}, message=${message}`)
}

async function factoryReceiptToContract (receipt, contractArtifact) {
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
    const marketReceipt = await factory.createCompoundERC20Market(marketTemplate.address, DEFAULT_SALT, cToken.address, comptroller.address, rewards.address, stablecoin.address)
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
    const marketReceipt = await factory.createHarvestMarket(marketTemplate.address, DEFAULT_SALT, vault.address, rewards.address, harvestStaking.address, stablecoin.address)
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

const moneyMarketModuleList = [
  {
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
  },
  {
    name: 'YVault',
    moduleGenerator: yvaultMoneyMarketModule
  }
]

// Tests
contract('ZeroCouponBond', accounts => {
  // Accounts
  const acc0 = accounts[0]
  const acc1 = accounts[1]
  const acc2 = accounts[2]
  const govTreasury = accounts[3]
  const devWallet = accounts[4]

  // Contract instances
  let stablecoin
  let dInterestPool
  let market
  let feeModel
  let interestModel
  let interestOracle
  let depositNFT
  let fundingMultitoken
  let mph
  let mphMinter
  let mphIssuanceModel
  let vesting
  let vesting02
  let factory
  let zeroCouponBond

  // Constants
  const INIT_INTEREST_RATE = 0.1 // 10% APY
  const INIT_INTEREST_RATE_PER_SECOND = 0.1 / YEAR_IN_SEC // 10% APY

  for (const moduleInfo of moneyMarketModuleList) {
    const moneyMarketModule = moduleInfo.moduleGenerator()
    context(`Money market: ${moduleInfo.name}`, () => {
      beforeEach(async () => {
        stablecoin = await ERC20Mock.new()

        // Mint stablecoin
        const mintAmount = 1000 * STABLECOIN_PRECISION
        await stablecoin.mint(acc0, num2str(mintAmount))
        await stablecoin.mint(acc1, num2str(mintAmount))
        await stablecoin.mint(acc2, num2str(mintAmount))

        // Initialize MPH
        mph = await MPHToken.new()
        await mph.init()
        vesting = await Vesting.new(mph.address)
        vesting02 = await Vesting02.new()
        mphIssuanceModel = await MPHIssuanceModel.new()
        await mphIssuanceModel.init(DevRewardMultiplier, GovRewardMultiplier)
        mphMinter = await MPHMinter.new()
        await mphMinter.init(mph.address, govTreasury, devWallet, mphIssuanceModel.address, vesting.address, vesting02.address)
        await vesting02.init(mphMinter.address, mph.address, 'Vested MPH', 'veMPH')
        await mph.transferOwnership(mphMinter.address)
        await mphMinter.grantRole(WHITELISTER_ROLE, acc0, { from: acc0 })

        // Set infinite MPH approval
        await mph.approve(mphMinter.address, INF, { from: acc0 })
        await mph.approve(mphMinter.address, INF, { from: acc1 })
        await mph.approve(mphMinter.address, INF, { from: acc2 })

        // Deploy factory
        factory = await Factory.new()

        // Deploy moneyMarket
        market = await moneyMarketModule.deployMoneyMarket(accounts, factory, stablecoin, govTreasury)

        // Initialize the NFTs
        const nftTemplate = await NFT.new()
        const depositNFTReceipt = await factory.createNFT(nftTemplate.address, DEFAULT_SALT, '88mph Deposit', '88mph-Deposit')
        depositNFT = await factoryReceiptToContract(depositNFTReceipt, NFT)
        const fundingMultitokenTemplate = await FundingMultitoken.new()
        const fundingNFTReceipt = await factory.createFundingMultitoken(fundingMultitokenTemplate.address, DEFAULT_SALT, stablecoin.address, 'https://api.88mph.app/funding-metadata/')
        fundingMultitoken = await factoryReceiptToContract(fundingNFTReceipt, FundingMultitoken)

        // Initialize the interest oracle
        const interestOracleTemplate = await EMAOracle.new()
        const interestOracleReceipt = await factory.createEMAOracle(interestOracleTemplate.address, DEFAULT_SALT, num2str(INIT_INTEREST_RATE * PRECISION / YEAR_IN_SEC), EMAUpdateInterval, EMASmoothingFactor, EMAAverageWindowInIntervals, market.address)
        interestOracle = await factoryReceiptToContract(interestOracleReceipt, EMAOracle)

        // Initialize the DInterest pool
        feeModel = await PercentageFeeModel.new(govTreasury)
        interestModel = await LinearDecayInterestModel.new(num2str(multiplierIntercept), num2str(multiplierSlope))
        const dInterestTemplate = await DInterest.new()
        const dInterestReceipt = await factory.createDInterest(
          dInterestTemplate.address,
          DEFAULT_SALT,
          MaxDepositPeriod,
          MinDepositAmount,
          market.address,
          stablecoin.address,
          feeModel.address,
          interestModel.address,
          interestOracle.address,
          depositNFT.address,
          fundingMultitoken.address,
          mphMinter.address
        )
        dInterestPool = await factoryReceiptToContract(dInterestReceipt, DInterest)

        // Set MPH minting multiplier for DInterest pool
        await mphMinter.grantRole(WHITELISTED_POOL_ROLE, dInterestPool.address, { from: acc0 })
        await mphIssuanceModel.setPoolDepositorRewardMintMultiplier(dInterestPool.address, PoolDepositorRewardMintMultiplier)
        await mphIssuanceModel.setPoolFunderRewardMultiplier(dInterestPool.address, PoolFunderRewardMultiplier)
        await mphIssuanceModel.setPoolFunderRewardVestPeriod(dInterestPool.address, PoolFunderRewardVestPeriod)

        // Transfer the ownership of the money market to the DInterest pool
        await market.transferOwnership(dInterestPool.address)

        // Transfer NFT ownerships to the DInterest pool
        await depositNFT.transferOwnership(dInterestPool.address)
        await fundingMultitoken.grantRole(MINTER_BURNER_ROLE, dInterestPool.address)
        await fundingMultitoken.grantRole(DIVIDEND_ROLE, dInterestPool.address)

        // Deploy ZeroCouponBond
        const zeroCouponBondTemplate = await ZeroCouponBond.new()
        const blockNow = await latestBlockTimestamp()
        const zeroCouponBondAddress = await factory.predictAddress(zeroCouponBondTemplate.address, DEFAULT_SALT)
        await stablecoin.approve(zeroCouponBondAddress, num2str(MinDepositAmount))
        const zcbReceipt = await factory.createZeroCouponBond(
          zeroCouponBondTemplate.address,
          DEFAULT_SALT,
          dInterestPool.address,
          num2str(blockNow + 2 * YEAR_IN_SEC),
          num2str(MinDepositAmount),
          '88mph Zero Coupon Bond',
          'MPHZCB-Jan-2023',
          { from: acc0 }
        )
        zeroCouponBond = await factoryReceiptToContract(zcbReceipt, ZeroCouponBond)
      })

      describe('mint', () => {
        context('happy path', () => {

        })

        context('edge cases', () => {

        })
      })

      describe('earlyRedeem', () => {
        context('happy path', () => {

        })

        context('edge cases', () => {

        })
      })

      describe('withdrawDeposit', () => {
        context('happy path', () => {

        })

        context('edge cases', () => {

        })
      })

      describe('redeem', () => {
        context('happy path', () => {

        })

        context('edge cases', () => {

        })
      })
    })
  }
})
