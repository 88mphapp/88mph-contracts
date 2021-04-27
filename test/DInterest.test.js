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
const Rewards = artifacts.require('Rewards')
const EMAOracle = artifacts.require('EMAOracle')
const MPHIssuanceModel = artifacts.require('MPHIssuanceModel01')
const Vesting = artifacts.require('Vesting')

// Constants
const PRECISION = 1e18
const STABLECOIN_PRECISION = 1e6
const YEAR_IN_SEC = 31556952 // Number of seconds in a year
const multiplierIntercept = 0.5 * PRECISION
const multiplierSlope = 0.25 / YEAR_IN_SEC * PRECISION
const MaxDepositPeriod = 3 * YEAR_IN_SEC // 3 years in seconds
const MinDepositAmount = BigNumber(0.1 * STABLECOIN_PRECISION).toFixed() // 0.1 stablecoin
const PoolDepositorRewardMintMultiplier = BigNumber(3.168873e-13 * PRECISION * (PRECISION / STABLECOIN_PRECISION)).toFixed() // 1e5 stablecoin * 1 year => 1 MPH
const PoolDepositorRewardTakeBackMultiplier = BigNumber(0.9 * PRECISION).toFixed()
const PoolFunderRewardMultiplier = BigNumber(3.168873e-13 * PRECISION * (PRECISION / STABLECOIN_PRECISION)).toFixed() // 1e5 stablecoin * 1 year => 1 MPH
const DevRewardMultiplier = BigNumber(0.1 * PRECISION).toFixed()
const EMAUpdateInterval = 24 * 60 * 60
const EMASmoothingFactor = BigNumber(2 * PRECISION).toFixed()
const EMAAverageWindowInIntervals = 30
const PoolDepositorRewardVestPeriod = 7 * 24 * 60 * 60 // 7 days
const PoolFunderRewardVestPeriod = 0 * 24 * 60 * 60 // 0 days
const MINTER_BURNER_ROLE = web3.utils.soliditySha3('MINTER_BURNER_ROLE')
const DIVIDEND_ROLE = web3.utils.soliditySha3('DIVIDEND_ROLE')

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

function calcInterestAmount (depositAmount, interestRatePerSecond, depositPeriodInSeconds, applyFee) {
  const IRMultiplier = getIRMultiplier(depositPeriodInSeconds)
  const interestBeforeFee = BigNumber(depositAmount).times(depositPeriodInSeconds).times(interestRatePerSecond).times(IRMultiplier)
  return applyFee ? interestBeforeFee.minus(calcFeeAmount(interestBeforeFee)) : interestBeforeFee
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
  /* {
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
  }, */
  {
    name: 'YVault',
    moduleGenerator: yvaultMoneyMarketModule
  }
]

// Tests
contract('DInterest', accounts => {
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
  let rewards
  let mphIssuanceModel
  let vesting
  let factory

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
        mphIssuanceModel = await MPHIssuanceModel.new(DevRewardMultiplier)
        mphMinter = await MPHMinter.new(mph.address, govTreasury, devWallet, mphIssuanceModel.address, vesting.address)
        mph.transferOwnership(mphMinter.address)

        // Set infinite MPH approval
        await mph.approve(mphMinter.address, INF, { from: acc0 })
        await mph.approve(mphMinter.address, INF, { from: acc1 })
        await mph.approve(mphMinter.address, INF, { from: acc2 })

        // Initialize MPH rewards
        rewards = await Rewards.new(mph.address, stablecoin.address, Math.floor(Date.now() / 1e3))
        rewards.setRewardDistribution(acc0, true)

        // Deploy factory
        factory = await Factory.new()

        // Deploy moneyMarket
        market = await moneyMarketModule.deployMoneyMarket(accounts, factory, stablecoin, rewards)

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
        feeModel = await PercentageFeeModel.new(rewards.address)
        interestModel = await LinearDecayInterestModel.new(num2str(multiplierIntercept), num2str(multiplierSlope))
        dInterestPool = await DInterest.new(
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

        // Set MPH minting multiplier for DInterest pool
        await mphMinter.setPoolWhitelist(dInterestPool.address, true)
        await mphIssuanceModel.setPoolDepositorRewardMintMultiplier(dInterestPool.address, PoolDepositorRewardMintMultiplier)
        await mphIssuanceModel.setPoolDepositorRewardTakeBackMultiplier(dInterestPool.address, PoolDepositorRewardTakeBackMultiplier)
        await mphIssuanceModel.setPoolFunderRewardMultiplier(dInterestPool.address, PoolFunderRewardMultiplier)
        await mphIssuanceModel.setPoolDepositorRewardVestPeriod(dInterestPool.address, PoolDepositorRewardVestPeriod)
        await mphIssuanceModel.setPoolFunderRewardVestPeriod(dInterestPool.address, PoolFunderRewardVestPeriod)

        // Transfer the ownership of the money market to the DInterest pool
        await market.transferOwnership(dInterestPool.address)

        // Transfer NFT ownerships to the DInterest pool
        await depositNFT.transferOwnership(dInterestPool.address)
        await fundingMultitoken.grantRole(MINTER_BURNER_ROLE, dInterestPool.address)
        await fundingMultitoken.grantRole(DIVIDEND_ROLE, dInterestPool.address)
      })

      describe('deposit', () => {
        context('happy path', () => {
          it('should update global variables correctly', async () => {
            const depositAmount = 100 * STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
            const blockNow = await latestBlockTimestamp()
            await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

            // Calculate interest amount
            const expectedInterest = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, true)

            // Verify totalDeposit
            const totalDeposit = BigNumber(await dInterestPool.totalDeposit())
            assertEpsilonEq(totalDeposit, depositAmount, 'totalDeposit not updated after acc0 deposited')

            // Verify totalInterestOwed
            const totalInterestOwed = BigNumber(await dInterestPool.totalInterestOwed())
            assertEpsilonEq(totalInterestOwed, expectedInterest, 'totalInterestOwed not updated after acc0 deposited')

            // Verify totalFeeOwed
            const totalFeeOwed = BigNumber(await dInterestPool.totalFeeOwed())
            const expectedTotalFeeOwed = totalInterestOwed.plus(totalFeeOwed).minus(applyFee(totalInterestOwed.plus(totalFeeOwed)))
            assertEpsilonEq(totalFeeOwed, expectedTotalFeeOwed, 'totalFeeOwed not updated after acc0 deposited')
          })

          it('should transfer funds correctly', async () => {
            const depositAmount = 100 * STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
            const blockNow = await latestBlockTimestamp()
            const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
            const dInterestPoolBeforeBalance = BigNumber(await market.totalValue.call())
            await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

            const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
            const dInterestPoolCurrentBalance = BigNumber(await market.totalValue.call())

            // Verify stablecoin transferred out of account
            assertEpsilonEq(acc0BeforeBalance.minus(acc0CurrentBalance), depositAmount, 'stablecoin not transferred out of acc0')

            // Verify stablecoin transferred into money market
            assertEpsilonEq(dInterestPoolCurrentBalance.minus(dInterestPoolBeforeBalance), depositAmount, 'stablecoin not transferred into money market')
          })
        })

        context('edge cases', () => {
          it('should fail with very short deposit period', async () => {
            const depositAmount = 100 * STABLECOIN_PRECISION

            // acc0 deposits for 1 second
            await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
            const blockNow = await latestBlockTimestamp()
            try {
              await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + 1), { from: acc0 })
              assert.fail()
            } catch (error) { }
          })

          it('should fail with greater than maximum deposit period', async function () {
            const depositAmount = 100 * STABLECOIN_PRECISION

            // acc0 deposits for 10 years
            await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
            const blockNow = await latestBlockTimestamp()
            try {
              await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + 10 * YEAR_IN_SEC), { from: acc0 })
              assert.fail()
            } catch (error) { }
          })

          it('should fail with less than minimum deposit amount', async function () {
            const depositAmount = 0.001 * STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
            const blockNow = await latestBlockTimestamp()
            try {
              await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })
              assert.fail()
            } catch (error) { }
          })
        })
      })

      describe('topupDeposit', () => {
        context('happy path', () => {

        })

        context('edge cases', () => {

        })
      })

      describe('rolloverDeposit', () => {
        context('happy path', () => {

        })

        context('edge cases', () => {

        })
      })

      describe('withdraw', () => {
        context('withdraw after maturation', () => {
          const depositAmount = 100 * STABLECOIN_PRECISION

          beforeEach(async () => {
            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
            const blockNow = await latestBlockTimestamp()
            await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

            // Wait 1 year
            await moneyMarketModule.timePass(1)
          })

          context('full withdrawal', () => {
            it('should update global variables correctly', async () => {
              // Withdraw
              await dInterestPool.withdraw(1, INF, false, { from: acc0 })

              // Verify totalDeposit
              const totalDeposit = BigNumber(await dInterestPool.totalDeposit())
              assertEpsilonEq(totalDeposit, 0, 'totalDeposit incorrect')

              // Verify totalInterestOwed
              const totalInterestOwed = BigNumber(await dInterestPool.totalInterestOwed())
              assertEpsilonEq(totalInterestOwed, 0, 'totalInterestOwed incorrect')

              // Verify totalFeeOwed
              const totalFeeOwed = BigNumber(await dInterestPool.totalFeeOwed())
              assertEpsilonEq(totalFeeOwed, 0, 'totalFeeOwed incorrect')
            })

            it('should transfer funds correctly', async function () {
              const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolBeforeBalance = BigNumber(await market.totalValue.call())

              // Withdraw
              await dInterestPool.withdraw(1, INF, false, { from: acc0 })

              const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolCurrentBalance = BigNumber(await market.totalValue.call())

              // Verify stablecoin transferred into account
              const expectedInterest = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, true)
              const expectedWithdrawAmount = expectedInterest.plus(depositAmount)
              assertEpsilonEq(acc0CurrentBalance.minus(acc0BeforeBalance), expectedWithdrawAmount, 'stablecoin not transferred into acc0')

              // Verify stablecoin transferred into money market
              const actualPoolValueChange = dInterestPoolBeforeBalance.minus(dInterestPoolCurrentBalance)
              const expectedPoolValueChange = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, false).plus(depositAmount)
              assertEpsilonEq(actualPoolValueChange, expectedPoolValueChange, 'stablecoin not transferred out of money market')
            })
          })

          context('partial withdrawal', async () => {
            const withdrawProportion = 0.7
            let virtualTokenTotalSupply, withdrawVirtualTokenAmount

            beforeEach(async () => {
              virtualTokenTotalSupply = BigNumber((await dInterestPool.getDeposit(1)).virtualTokenTotalSupply)
              withdrawVirtualTokenAmount = virtualTokenTotalSupply.times(withdrawProportion).integerValue()
            })

            it('should update global variables correctly', async () => {
              // Withdraw
              await dInterestPool.withdraw(1, num2str(withdrawVirtualTokenAmount), false, { from: acc0 })

              // Verify totalDeposit
              const totalDeposit = BigNumber(await dInterestPool.totalDeposit())
              assertEpsilonEq(totalDeposit, depositAmount * (1 - withdrawProportion), 'totalDeposit incorrect')

              // Verify totalInterestOwed
              const totalInterestOwed = BigNumber(await dInterestPool.totalInterestOwed())
              const expectedInterest = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, true).times(1 - withdrawProportion)
              assertEpsilonEq(totalInterestOwed, expectedInterest, 'totalInterestOwed incorrect')

              // Verify totalFeeOwed
              const totalFeeOwed = BigNumber(await dInterestPool.totalFeeOwed())
              const expectedTotalFeeOwed = calcFeeAmount(calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, false)).times(1 - withdrawProportion)
              assertEpsilonEq(totalFeeOwed, expectedTotalFeeOwed, 'totalFeeOwed incorrect')
            })

            it('should transfer funds correctly', async function () {
              const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolBeforeBalance = BigNumber(await market.totalValue.call())

              // Withdraw
              await dInterestPool.withdraw(1, num2str(withdrawVirtualTokenAmount), false, { from: acc0 })

              const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolCurrentBalance = BigNumber(await market.totalValue.call())

              // Verify stablecoin transferred into account
              const expectedInterest = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, true)
              const expectedWithdrawAmount = expectedInterest.plus(depositAmount).times(withdrawProportion)
              assertEpsilonEq(acc0CurrentBalance.minus(acc0BeforeBalance), expectedWithdrawAmount, 'stablecoin not transferred into acc0')

              // Verify stablecoin transferred into money market
              const actualPoolValueChange = dInterestPoolBeforeBalance.minus(dInterestPoolCurrentBalance)
              const expectedPoolValueChange = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, false).plus(depositAmount).times(withdrawProportion)
              assertEpsilonEq(actualPoolValueChange, expectedPoolValueChange, 'stablecoin not transferred out of money market')
            })
          })
        })

        context('withdraw before maturation', () => {
          const depositAmount = 100 * STABLECOIN_PRECISION

          beforeEach(async () => {
            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
            const blockNow = await latestBlockTimestamp()
            await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

            // Wait 0.5 year
            await moneyMarketModule.timePass(0.5)
          })

          context('full withdrawal', () => {
            it('should update global variables correctly', async () => {
              // Withdraw
              await dInterestPool.withdraw(1, INF, true, { from: acc0 })

              // Verify totalDeposit
              const totalDeposit = BigNumber(await dInterestPool.totalDeposit())
              assertEpsilonEq(totalDeposit, 0, 'totalDeposit incorrect')

              // Verify totalInterestOwed
              const totalInterestOwed = BigNumber(await dInterestPool.totalInterestOwed())
              assertEpsilonEq(totalInterestOwed, 0, 'totalInterestOwed incorrect')

              // Verify totalFeeOwed
              const totalFeeOwed = BigNumber(await dInterestPool.totalFeeOwed())
              assertEpsilonEq(totalFeeOwed, 0, 'totalFeeOwed incorrect')
            })

            it('should transfer funds correctly', async () => {
              const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolBeforeBalance = BigNumber(await market.totalValue.call())

              // Withdraw
              await dInterestPool.withdraw(1, INF, true, { from: acc0 })

              const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolCurrentBalance = BigNumber(await market.totalValue.call())

              // Verify stablecoin transferred into account
              assertEpsilonEq(acc0CurrentBalance.minus(acc0BeforeBalance), depositAmount, 'stablecoin not transferred into acc0')

              // Verify stablecoin transferred into money market
              const actualPoolValueChange = dInterestPoolBeforeBalance.minus(dInterestPoolCurrentBalance)
              assertEpsilonEq(actualPoolValueChange, depositAmount, 'stablecoin not transferred out of money market')
            })
          })

          context('partial withdrawal', async () => {
            const withdrawProportion = 0.7
            let virtualTokenTotalSupply, withdrawVirtualTokenAmount

            beforeEach(async () => {
              virtualTokenTotalSupply = BigNumber((await dInterestPool.getDeposit(1)).virtualTokenTotalSupply)
              withdrawVirtualTokenAmount = virtualTokenTotalSupply.times(withdrawProportion).integerValue()
            })

            it('should update global variables correctly', async () => {
              // Withdraw
              await dInterestPool.withdraw(1, num2str(withdrawVirtualTokenAmount), true, { from: acc0 })

              // Verify totalDeposit
              const totalDeposit = BigNumber(await dInterestPool.totalDeposit())
              assertEpsilonEq(totalDeposit, depositAmount * (1 - withdrawProportion), 'totalDeposit incorrect')

              // Verify totalInterestOwed
              const totalInterestOwed = BigNumber(await dInterestPool.totalInterestOwed())
              const expectedInterest = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, true).times(1 - withdrawProportion)
              assertEpsilonEq(totalInterestOwed, expectedInterest, 'totalInterestOwed incorrect')

              // Verify totalFeeOwed
              const totalFeeOwed = BigNumber(await dInterestPool.totalFeeOwed())
              const expectedTotalFeeOwed = calcFeeAmount(calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, false)).times(1 - withdrawProportion)
              assertEpsilonEq(totalFeeOwed, expectedTotalFeeOwed, 'totalFeeOwed incorrect')
            })

            it('should transfer funds correctly', async function () {
              const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolBeforeBalance = BigNumber(await market.totalValue.call())

              // Withdraw
              await dInterestPool.withdraw(1, num2str(withdrawVirtualTokenAmount), true, { from: acc0 })

              const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolCurrentBalance = BigNumber(await market.totalValue.call())

              // Verify stablecoin transferred into account
              const expectedWithdrawAmount = BigNumber(depositAmount).times(withdrawProportion)
              assertEpsilonEq(acc0CurrentBalance.minus(acc0BeforeBalance), expectedWithdrawAmount, 'stablecoin not transferred into acc0')

              // Verify stablecoin transferred into money market
              const actualPoolValueChange = dInterestPoolBeforeBalance.minus(dInterestPoolCurrentBalance)
              const expectedPoolValueChange = BigNumber(depositAmount).times(withdrawProportion)
              assertEpsilonEq(actualPoolValueChange, expectedPoolValueChange, 'stablecoin not transferred out of money market')
            })
          })
        })

        context('complex examples', () => {
          it('two deposits with overlap', async () => {
            const depositAmount = 10 * STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
            let blockNow = await latestBlockTimestamp()
            await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc0 })

            // Wait 0.5 year
            await moneyMarketModule.timePass(0.5)

            // acc1 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc1 })
            blockNow = await latestBlockTimestamp()
            await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc1 })

            // Wait 0.5 year
            await moneyMarketModule.timePass(0.5)

            // acc0 withdraws
            const acc0BeforeBalance = await stablecoin.balanceOf(acc0)
            await dInterestPool.withdraw(1, INF, false, { from: acc0 })

            // Verify withdrawn amount
            const acc0CurrentBalance = await stablecoin.balanceOf(acc0)
            const acc0WithdrawnAmountExpected = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, true).plus(depositAmount)
            const acc0WithdrawnAmountActual = BigNumber(acc0CurrentBalance).minus(acc0BeforeBalance)
            assertEpsilonEq(acc0WithdrawnAmountActual, acc0WithdrawnAmountExpected, 'acc0 didn\'t withdraw correct amount of stablecoin')

            // Verify totalDeposit
            const totalDeposit0 = BigNumber(await dInterestPool.totalDeposit())
            assertEpsilonEq(totalDeposit0, depositAmount, 'totalDeposit not updated after acc0 withdrawed')

            // Wait 0.5 year
            await moneyMarketModule.timePass(0.5)

            // acc1 withdraws
            const acc1BeforeBalance = await stablecoin.balanceOf(acc1)
            await dInterestPool.withdraw(2, INF, false, { from: acc1 })

            // Verify withdrawn amount
            const acc1CurrentBalance = await stablecoin.balanceOf(acc1)
            const acc1WithdrawnAmountExpected = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, true).plus(depositAmount)
            const acc1WithdrawnAmountActual = BigNumber(acc1CurrentBalance).minus(acc1BeforeBalance)
            assertEpsilonEq(acc1WithdrawnAmountActual, acc1WithdrawnAmountExpected, 'acc1 didn\'t withdraw correct amount of stablecoin')

            // Verify totalDeposit
            const totalDeposit1 = BigNumber(await dInterestPool.totalDeposit())
            assertEpsilonEq(totalDeposit1, 0, 'totalDeposit not updated after acc1 withdrawed')
          })
        })

        context('edge cases', () => {

        })
      })

      describe('fund', () => {
        context('happy path', () => {
          it('fund 10% at the beginning', async () => {
            const depositAmount = 100 * STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
            const blockNow = await latestBlockTimestamp()
            await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

            // acc1 funds deposit
            await stablecoin.approve(dInterestPool.address, INF, { from: acc1 })
            await dInterestPool.fund(1, INF, { from: acc1 })

            // wait 1 year
            await moneyMarketModule.timePass(1)

            // withdraw deposit
            await dInterestPool.withdraw(1, INF, false, { from: acc0 })

            // verify earned interest
            const acc1BeforeBalance = BigNumber(await stablecoin.balanceOf(acc1))
            await fundingMultitoken.withdrawDividend(1, { from: acc1 })
            const actualInterestAmount = BigNumber(await stablecoin.balanceOf(acc1)).minus(acc1BeforeBalance)
            const expectedInterestAmount = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, false).plus(depositAmount).times(INIT_INTEREST_RATE)
            assertEpsilonEq(actualInterestAmount, expectedInterestAmount, 'funding interest earned incorrect')
          })

          it('two funders fund 70% at 20% maturation', async () => {
            const depositAmount = 100 * STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
            const blockNow = await latestBlockTimestamp()
            await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

            // wait 0.2 year
            await moneyMarketModule.timePass(0.2)

            // acc1 funds 50%
            await stablecoin.approve(dInterestPool.address, INF, { from: acc1 })
            const deficitAmount = BigNumber((await dInterestPool.surplusOfDeposit.call(1)).surplusAmount)
            await dInterestPool.fund(1, num2str(deficitAmount.times(0.5)), { from: acc1 })

            // acc1 funds 20%
            await stablecoin.approve(dInterestPool.address, INF, { from: acc2 })
            await dInterestPool.fund(1, num2str(deficitAmount.times(0.2)), { from: acc2 })

            // wait 0.8 year
            await moneyMarketModule.timePass(0.8)

            // withdraw deposit
            await dInterestPool.withdraw(1, INF, false, { from: acc0 })

            // verify earned interest
            const acc1BeforeBalance = BigNumber(await stablecoin.balanceOf(acc1))
            await fundingMultitoken.withdrawDividend(1, { from: acc1 })
            const actualAcc1InterestAmount = BigNumber(await stablecoin.balanceOf(acc1)).minus(acc1BeforeBalance)
            const expectedAcc1InterestAmount = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, false).plus(depositAmount).times(INIT_INTEREST_RATE).times(0.8).times(0.5)
            assertEpsilonEq(actualAcc1InterestAmount, expectedAcc1InterestAmount, 'acc1 funding interest earned incorrect')

            const acc2BeforeBalance = BigNumber(await stablecoin.balanceOf(acc2))
            await fundingMultitoken.withdrawDividend(1, { from: acc2 })
            const actualAcc2InterestAmount = BigNumber(await stablecoin.balanceOf(acc2)).minus(acc2BeforeBalance)
            const expectedAcc2InterestAmount = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, false).plus(depositAmount).times(INIT_INTEREST_RATE).times(0.8).times(0.2)
            assertEpsilonEq(actualAcc2InterestAmount, expectedAcc2InterestAmount, 'acc2 funding interest earned incorrect')
          })

          it('fund 10% then withdraw 50%', async () => {
            const depositAmount = 100 * STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
            const blockNow = await latestBlockTimestamp()
            await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

            // acc1 funds 10%
            await stablecoin.approve(dInterestPool.address, INF, { from: acc1 })
            const deficitAmount = BigNumber((await dInterestPool.surplusOfDeposit.call(1)).surplusAmount)
            await dInterestPool.fund(1, num2str(deficitAmount.times(0.1)), { from: acc1 })

            // withdraw 50%
            const depositVirtualTokenTotalSupply = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, true).plus(depositAmount)
            await dInterestPool.withdraw(1, num2str(depositVirtualTokenTotalSupply.times(0.5)), true, { from: acc0 })

            // wait 1 year
            await moneyMarketModule.timePass(1)

            // withdraw deposit
            await dInterestPool.withdraw(1, INF, false, { from: acc0 })

            // verify earned interest
            const acc1BeforeBalance = BigNumber(await stablecoin.balanceOf(acc1))
            await fundingMultitoken.withdrawDividend(1, { from: acc1 })
            const actualInterestAmount = BigNumber(await stablecoin.balanceOf(acc1)).minus(acc1BeforeBalance)
            const expectedInterestAmount = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, false).plus(depositAmount).times(INIT_INTEREST_RATE).times(0.1)
            assertEpsilonEq(actualInterestAmount, expectedInterestAmount, 'funding interest earned incorrect')
          })

          it('fund 90% then withdraw 50%', async () => {
            const depositAmount = 100 * STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
            const blockNow = await latestBlockTimestamp()
            await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

            // acc1 funds 90%
            await stablecoin.approve(dInterestPool.address, INF, { from: acc1 })
            const deficitAmount = BigNumber((await dInterestPool.surplusOfDeposit.call(1)).surplusAmount)
            await dInterestPool.fund(1, num2str(deficitAmount.times(0.9)), { from: acc1 })

            // withdraw 50%
            const depositVirtualTokenTotalSupply = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, true).plus(depositAmount)
            await dInterestPool.withdraw(1, num2str(depositVirtualTokenTotalSupply.times(0.5)), true, { from: acc0 })

            // verify refund
            {
              const acc1BeforeBalance = BigNumber(await stablecoin.balanceOf(acc1))
              await fundingMultitoken.withdrawDividend(1, { from: acc1 })
              const actualRefundAmount = BigNumber(await stablecoin.balanceOf(acc1)).minus(acc1BeforeBalance)
              const estimatedLostInterest = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, false).plus(depositAmount).times(INIT_INTEREST_RATE).times(0.9 + 0.5 - 1)
              const maxRefundAmount = deficitAmount.times(0.4)
              const expectedRefundAmount = BigNumber.min(estimatedLostInterest, maxRefundAmount)
              assertEpsilonEq(actualRefundAmount, expectedRefundAmount, 'funding refund incorrect')
            }

            // wait 1 year
            await moneyMarketModule.timePass(1)

            // withdraw deposit
            await dInterestPool.withdraw(1, INF, false, { from: acc0 })

            // verify earned interest
            const acc1BeforeBalance = BigNumber(await stablecoin.balanceOf(acc1))
            await fundingMultitoken.withdrawDividend(1, { from: acc1 })
            const actualInterestAmount = BigNumber(await stablecoin.balanceOf(acc1)).minus(acc1BeforeBalance)
            const expectedInterestAmount = calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, YEAR_IN_SEC, false).plus(depositAmount).times(INIT_INTEREST_RATE).times(0.5)
            assertEpsilonEq(actualInterestAmount, expectedInterestAmount, 'funding interest earned incorrect')
          })
        })

        context('complex cases', () => {
          it('one funder funds 10% at the beginning, then another funder funds 70% at 50% maturation', async () => {

          })
        })

        context('edge cases', () => {
          it('fund 90%, withdraw 100%, topup', async () => {

          })

          it('fund 90%, withdraw 99.99%, topup', async () => {

          })
        })
      })

      describe('payInterestToFunders', () => {
        context('happy path', () => {

        })

        context('edge cases', () => {

        })
      })

      describe('calculateInterestAmount', () => {
        context('happy path', () => {

        })

        context('edge cases', () => {

        })
      })

      describe('totalInterestOwedToFunders', () => {
        context('happy path', () => {

        })

        context('edge cases', () => {

        })
      })

      describe('surplus', () => {
        context('happy path', () => {

        })

        context('edge cases', () => {

        })
      })

      describe('rawSurplusOfDeposit', () => {
        context('happy path', () => {

        })

        context('edge cases', () => {

        })
      })

      describe('surplusOfDeposit', () => {
        context('happy path', () => {

        })

        context('edge cases', () => {

        })
      })

      describe('withdrawableAmountOfDeposit', () => {
        context('happy path', () => {

        })

        context('edge cases', () => {

        })
      })

      describe('accruedInterestOfFunding', () => {
        context('happy path', () => {

        })

        context('edge cases', () => {

        })
      })
    })
  }
})
