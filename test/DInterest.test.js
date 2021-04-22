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
  return await contractArtifact.at(receipt.logs[receipt.logs.length - 1].args._clone)
}

const aaveMoneyMarketModule = () => {
  let aToken
  let lendingPool
  let lendingPoolAddressesProvider

  const deployMoneyMarket = async (factory, stablecoin) => {
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
    const marketReceipt = await factory.createAaveMarket(marketTemplate.address, lendingPoolAddressesProvider.address, aToken.address, stablecoin.address)
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

// Tests
contract('DInterest', accounts => {
  const moneyMarketModule = aaveMoneyMarketModule()

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
    market = await moneyMarketModule.deployMoneyMarket(factory, stablecoin)

    // Initialize the NFTs
    const nftTemplate = await NFT.new()
    const depositNFTReceipt = await factory.createNFT(nftTemplate.address, '88mph Deposit', '88mph-Deposit')
    depositNFT = await factoryReceiptToContract(depositNFTReceipt, NFT)
    const fundingMultitokenTemplate = await FundingMultitoken.new()
    const fundingNFTReceipt = await factory.createFundingMultitoken(fundingMultitokenTemplate.address, stablecoin.address, 'https://api.88mph.app/funding-metadata/')
    fundingMultitoken = await factoryReceiptToContract(fundingNFTReceipt, FundingMultitoken)

    // Initialize the interest oracle
    const interestOracleTemplate = await EMAOracle.new()
    const interestOracleReceipt = await factory.createEMAOracle(interestOracleTemplate.address, num2str(INIT_INTEREST_RATE * PRECISION / YEAR_IN_SEC), EMAUpdateInterval, EMASmoothingFactor, EMAAverageWindowInIntervals, market.address)
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
        const dInterestPoolBeforeBalance = BigNumber(await market.totalValue())
        await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

        const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
        const dInterestPoolCurrentBalance = BigNumber(await market.totalValue())

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
          const dInterestPoolBeforeBalance = BigNumber(await market.totalValue())

          // Withdraw
          await dInterestPool.withdraw(1, INF, false, { from: acc0 })

          const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
          const dInterestPoolCurrentBalance = BigNumber(await market.totalValue())

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
          const dInterestPoolBeforeBalance = BigNumber(await market.totalValue())

          // Withdraw
          await dInterestPool.withdraw(1, num2str(withdrawVirtualTokenAmount), false, { from: acc0 })

          const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
          const dInterestPoolCurrentBalance = BigNumber(await market.totalValue())

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
          const dInterestPoolBeforeBalance = BigNumber(await market.totalValue())

          // Withdraw
          await dInterestPool.withdraw(1, INF, true, { from: acc0 })

          const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
          const dInterestPoolCurrentBalance = BigNumber(await market.totalValue())

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
          const dInterestPoolBeforeBalance = BigNumber(await market.totalValue())

          // Withdraw
          await dInterestPool.withdraw(1, num2str(withdrawVirtualTokenAmount), true, { from: acc0 })

          const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
          const dInterestPoolCurrentBalance = BigNumber(await market.totalValue())

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

    })

    context('edge cases', () => {

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
