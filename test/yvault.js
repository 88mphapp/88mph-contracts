// Libraries
const BigNumber = require('bignumber.js')

// Contract artifacts
const DInterest = artifacts.require('DInterest')
const PercentageFeeModel = artifacts.require('PercentageFeeModel')
const LinearInterestModel = artifacts.require('LinearInterestModel')
const NFT = artifacts.require('NFT')
const MPHToken = artifacts.require('MPHToken')
const MPHMinter = artifacts.require('MPHMinter')
const ERC20Mock = artifacts.require('ERC20Mock')
const Rewards = artifacts.require('Rewards')
const EMAOracle = artifacts.require('EMAOracle')
const MPHIssuanceModel = artifacts.require('MPHIssuanceModel01')
const Vesting = artifacts.require('Vesting')

const VaultMock = artifacts.require('VaultMock')
const YVaultMarket = artifacts.require('YVaultMarket')

// Constants
const PRECISION = 1e18
const STABLECOIN_PRECISION = 1e6
const YEAR_IN_SEC = 31556952 // Number of seconds in a year
const IRMultiplier = 0.75 // Minimum safe avg interest rate multiplier
const MinDepositPeriod = 90 * 24 * 60 * 60 // 90 days in seconds
const MaxDepositPeriod = 3 * YEAR_IN_SEC // 3 years in seconds
const MinDepositAmount = BigNumber(0 * PRECISION).toFixed() // 0 stablecoins
const MaxDepositAmount = BigNumber(1000 * PRECISION).toFixed() // 1000 stablecoins
const PoolDepositorRewardMintMultiplier = BigNumber(3.168873e-13 * PRECISION * (PRECISION / STABLECOIN_PRECISION)).toFixed() // 1e5 stablecoin * 1 year => 1 MPH
const PoolDepositorRewardTakeBackMultiplier = BigNumber(0.9 * PRECISION).toFixed()
const PoolFunderRewardMultiplier = BigNumber(3.168873e-13 * PRECISION * (PRECISION / STABLECOIN_PRECISION)).toFixed() // 1e5 stablecoin * 1 year => 1 MPH
const DevRewardMultiplier = BigNumber(0.1 * PRECISION).toFixed()
const EMAUpdateInterval = 24 * 60 * 60
const EMASmoothingFactor = BigNumber(2 * PRECISION).toFixed()
const EMAAverageWindowInIntervals = 30
const PoolDepositorRewardVestPeriod = 7 * 24 * 60 * 60 // 7 days
const PoolFunderRewardVestPeriod = 0 * 24 * 60 * 60 // 0 days

const epsilon = 1e-4
const INF = BigNumber(2).pow(256).minus(1).toFixed()
const ZERO_ADDR = '0x0000000000000000000000000000000000000000'

// Utilities
// travel `time` seconds forward in time
function timeTravel(time) {
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

async function latestBlockTimestamp() {
  return (await web3.eth.getBlock('latest')).timestamp
}

function calcFeeAmount(interestAmount) {
  return interestAmount.times(0.1)
}

function applyFee(interestAmount) {
  return interestAmount.minus(calcFeeAmount(interestAmount))
}

function calcInterestAmount(depositAmount, interestRatePerSecond, depositPeriodInSeconds, applyFee) {
  const interestBeforeFee = BigNumber(depositAmount).times(depositPeriodInSeconds).times(interestRatePerSecond).div(PRECISION).times(IRMultiplier)
  return applyFee ? interestBeforeFee.minus(calcFeeAmount(interestBeforeFee)) : interestBeforeFee
}

// Converts a JS number into a string that doesn't use scientific notation
function num2str(num) {
  return BigNumber(num).integerValue().toFixed()
}

function epsilonEq(curr, prev) {
  return BigNumber(curr).eq(prev) ||
    (!BigNumber(prev).isZero() && BigNumber(curr).minus(prev).div(prev).abs().lt(epsilon)) ||
    (!BigNumber(curr).isZero() && BigNumber(prev).minus(curr).div(curr).abs().lt(epsilon))
}

// Tests
contract('YVault', accounts => {
  // Accounts
  const acc0 = accounts[0]
  const acc1 = accounts[1]
  const acc2 = accounts[2]
  const govTreasury = accounts[3]
  const devWallet = accounts[4]

  // Contract instances
  let stablecoin
  let vault
  let dInterestPool
  let market
  let feeModel
  let interestModel
  let interestOracle
  let depositNFT
  let fundingNFT
  let mph
  let mphMinter
  let rewards
  let mphIssuanceModel
  let vesting

  // Constants
  const INIT_INTEREST_RATE = 0.1 // 10% APY

  const timePass = async (timeInYears) => {
    await timeTravel(timeInYears * YEAR_IN_SEC)
    await stablecoin.mint(vault.address, num2str(BigNumber(await stablecoin.balanceOf(vault.address)).times(INIT_INTEREST_RATE).times(timeInYears)))
  }

  beforeEach(async function () {
    // Initialize mock stablecoin and Aave
    stablecoin = await ERC20Mock.new()
    vault = await VaultMock.new(stablecoin.address)

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

    // Initialize the money market
    market = await YVaultMarket.new(vault.address, stablecoin.address)

    // Initialize the NFTs
    depositNFT = await NFT.new('88mph Deposit', '88mph-Deposit')
    fundingNFT = await NFT.new('88mph Funding', '88mph-Funding')

    // Initialize the interest oracle
    interestOracle = await EMAOracle.new(num2str(INIT_INTEREST_RATE * PRECISION / YEAR_IN_SEC), EMAUpdateInterval, EMASmoothingFactor, EMAAverageWindowInIntervals, market.address)

    // Initialize the DInterest pool
    feeModel = await PercentageFeeModel.new(rewards.address)
    interestModel = await LinearInterestModel.new(num2str(IRMultiplier * PRECISION))
    dInterestPool = await DInterest.new(
      {
        MinDepositPeriod,
        MaxDepositPeriod,
        MinDepositAmount,
        MaxDepositAmount
      },
      market.address,
      stablecoin.address,
      feeModel.address,
      interestModel.address,
      interestOracle.address,
      depositNFT.address,
      fundingNFT.address,
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
    await fundingNFT.transferOwnership(dInterestPool.address)
  })

  describe('normal operations', () => {
    it('deposit()', async function () {
      const depositAmount = 100 * STABLECOIN_PRECISION

      // acc0 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
      const blockNow = await latestBlockTimestamp()
      const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
      await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

      // Calculate interest amount
      const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
      const interestExpected = calcInterestAmount(depositAmount, BigNumber(INIT_INTEREST_RATE).times(PRECISION).div(YEAR_IN_SEC), num2str(YEAR_IN_SEC), false).div(STABLECOIN_PRECISION)

      // Verify stablecoin transfer
      assert.equal(acc0BeforeBalance.minus(acc0CurrentBalance).toNumber(), depositAmount, 'stablecoin not transferred out of acc0')

      // Verify totalDeposit
      const totalDeposit0 = BigNumber(await dInterestPool.totalDeposit())
      assert.equal(totalDeposit0.toNumber(), depositAmount, 'totalDeposit not updated after acc0 deposited')

      // Verify totalInterestOwed
      const totalInterestOwed = BigNumber(await dInterestPool.totalInterestOwed()).div(STABLECOIN_PRECISION)
      assert(epsilonEq(totalInterestOwed, interestExpected), 'totalInterestOwed not updated after acc0 deposited')
    })

    it('withdraw()', async function () {
      const depositAmount = 10 * STABLECOIN_PRECISION

      // acc0 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
      let blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc0 })

      // Wait 6 months
      await timePass(0.5)

      // acc1 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc1 })
      blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc1 })

      // Wait 6 months
      await timePass(0.5)

      // acc0 withdraws
      const acc0BeforeBalance = await stablecoin.balanceOf(acc0)
      await vesting.withdrawVested(acc0, 0, { from: acc0 })
      await dInterestPool.withdraw(1, 0, { from: acc0 })

      // try withdrawing again (should fail)
      try {
        await dInterestPool.withdraw(1, 0, { from: acc0 })
        assert.fail('acc0 withdrew twice')
      } catch (error) { }

      // Verify withdrawn amount
      const acc0CurrentBalance = await stablecoin.balanceOf(acc0)
      const acc0WithdrawnAmountExpected = applyFee(BigNumber((await dInterestPool.getDeposit(1)).interestOwed)).plus(depositAmount)
      const acc0WithdrawnAmountActual = BigNumber(acc0CurrentBalance).minus(acc0BeforeBalance)
      assert(epsilonEq(acc0WithdrawnAmountActual, acc0WithdrawnAmountExpected), 'acc0 didn\'t withdraw correct amount of stablecoin')

      // Verify totalDeposit
      const totalDeposit0 = BigNumber(await dInterestPool.totalDeposit())
      assert(totalDeposit0.eq(depositAmount), 'totalDeposit not updated after acc0 withdrawed')

      // Wait 6 months
      await timePass(0.5)

      // acc1 withdraws
      const acc1BeforeBalance = await stablecoin.balanceOf(acc1)
      await vesting.withdrawVested(acc1, 0, { from: acc1 })
      await dInterestPool.withdraw(2, 0, { from: acc1 })

      // Verify withdrawn amount
      const acc1CurrentBalance = await stablecoin.balanceOf(acc1)
      const acc1WithdrawnAmountExpected = applyFee(BigNumber((await dInterestPool.getDeposit(2)).interestOwed)).plus(depositAmount)
      const acc1WithdrawnAmountActual = BigNumber(acc1CurrentBalance).minus(acc1BeforeBalance)
      assert(epsilonEq(acc1WithdrawnAmountActual, acc1WithdrawnAmountExpected), 'acc1 didn\'t withdraw correct amount of stablecoin')

      // Verify totalDeposit
      const totalDeposit1 = BigNumber(await dInterestPool.totalDeposit())
      assert(totalDeposit1.eq(0), 'totalDeposit not updated after acc1 withdrawed')
    })

    it('earlyWithdraw()', async function () {
      const depositAmount = 10 * STABLECOIN_PRECISION

      // acc0 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
      let blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc0 })

      // acc0 withdraws early
      await timePass(1 / 52) // 1 week
      const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
      await vesting.withdrawVested(acc0, 0, { from: acc0 })
      await dInterestPool.earlyWithdraw(1, 0, { from: acc0 })

      // Verify withdrawn amount
      const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
      assert(epsilonEq(acc0CurrentBalance.minus(acc0BeforeBalance).toNumber(), depositAmount), 'acc0 didn\'t withdraw correct amount of stablecoin')

      // Verify totalDeposit
      const totalDeposit0 = BigNumber(await dInterestPool.totalDeposit())
      assert(totalDeposit0.eq(0), 'totalDeposit not updated after acc0 withdrawed')

      // acc0 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
      blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc0 })

      // Wait 1 year
      await timePass(1)

      // acc0 tries to withdraw early but fails
      try {
        await vesting.withdrawVested(acc0, 1, { from: acc0 })
        await dInterestPool.earlyWithdraw(2, 0, { from: acc0 })
        assert.fail('Called earlyWithdraw() after maturation without error')
      } catch (e) { }
    })

    it('fundAll()', async function () {
      const depositAmount = 10 * STABLECOIN_PRECISION

      // acc0 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
      let blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc0 })

      // acc1 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc1 })
      blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc1 })

      // acc1 deposits stablecoin into the DInterest pool for 3 months
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc1 })
      blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + 0.25 * YEAR_IN_SEC, { from: acc1 })

      // Wait 3 months
      await timePass(0.25)

      // Withdraw deposit 3
      await vesting.withdrawVested(acc1, 1, { from: acc1 })
      await dInterestPool.withdraw(3, 0, { from: acc1 })

      // Fund all deficit using acc2
      await stablecoin.approve(dInterestPool.address, INF, { from: acc2 })
      await dInterestPool.fundAll({ from: acc2 })

      // Check deficit
      const surplusObj = await dInterestPool.surplus.call()
      assert(!surplusObj.isNegative || (surplusObj.isNegative && BigNumber(surplusObj.surplusAmount).div(STABLECOIN_PRECISION).lt(epsilon)), 'Surplus negative after funding all deposits')

      // Wait 9 months
      await timePass(0.75)

      // acc0, acc1 withdraw deposits
      const acc2BeforeBalance = BigNumber(await stablecoin.balanceOf(acc2))
      await vesting.withdrawVested(acc0, 0, { from: acc0 })
      await vesting.withdrawVested(acc1, 0, { from: acc1 })
      await dInterestPool.withdraw(1, 1, { from: acc0 })
      await dInterestPool.withdraw(2, 1, { from: acc1 })

      // Check interest earned by funder
      const acc2AfterBalance = BigNumber(await stablecoin.balanceOf(acc2))
      assert(epsilonEq(acc2AfterBalance.minus(acc2BeforeBalance), BigNumber(depositAmount).times(1 + IRMultiplier * INIT_INTEREST_RATE).times(2).times(INIT_INTEREST_RATE).times(0.75)), 'acc2 didn\'t receive correct interest amount')
    })

    it('fundMultiple()', async function () {
      const depositAmount = 10 * STABLECOIN_PRECISION

      // acc0 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
      let blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc0 })

      // acc1 deposits stablecoin into the DInterest pool for 3 months
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc1 })
      blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + 0.25 * YEAR_IN_SEC, { from: acc1 })

      // acc1 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc1 })
      blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc1 })

      // acc1 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc1 })
      blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc1 })

      // Wait 3 months
      await timePass(0.25)

      // Withdraw deposit 2
      await vesting.withdrawVested(acc1, 0, { from: acc0 })
      await dInterestPool.withdraw(2, 0, { from: acc1 })

      // Fund deficit for the first 3 deposits using acc2
      await stablecoin.approve(dInterestPool.address, INF, { from: acc2 })
      await dInterestPool.fundMultiple(3, { from: acc2 })

      // Check deficit
      // Deficits of deposits 1-3 are filled, so the pool's deficit/surplus should equal that of deposit 4
      const deposit4SurplusObj = await dInterestPool.surplusOfDeposit.call(4)
      const expectedSurplus = BigNumber(deposit4SurplusObj.surplusAmount).times(deposit4SurplusObj.isNegative ? -1 : 1)
      const surplusObj = await dInterestPool.surplus.call()
      const actualSurplus = BigNumber(surplusObj.surplusAmount).times(surplusObj.isNegative ? -1 : 1)
      assert(epsilonEq(actualSurplus, expectedSurplus), 'Incorrect surplus after funding')

      // Wait 9 months
      await timePass(0.75)

      // acc0, acc1 withdraw deposits
      const acc2BeforeBalance = BigNumber(await stablecoin.balanceOf(acc2))
      await vesting.withdrawVested(acc0, 0, { from: acc0 })
      await vesting.withdrawVested(acc1, 1, { from: acc0 })
      await vesting.withdrawVested(acc1, 2, { from: acc0 })
      await dInterestPool.withdraw(1, 1, { from: acc0 })
      await dInterestPool.withdraw(3, 1, { from: acc1 })
      await dInterestPool.withdraw(4, 0, { from: acc1 })

      // Check interest earned by funder
      const acc2AfterBalance = BigNumber(await stablecoin.balanceOf(acc2))
      assert(epsilonEq(acc2AfterBalance.minus(acc2BeforeBalance), BigNumber(depositAmount).times(1 + IRMultiplier * INIT_INTEREST_RATE).times(2).times(INIT_INTEREST_RATE).times(0.75)), 'acc2 didn\'t receive correct interest amount')
    })

    it('totalInterestOwedToFunders()', async () => {
      const depositAmount = 10 * STABLECOIN_PRECISION

      // acc0 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
      let blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc0 })

      // Fund all deficit using acc2
      await stablecoin.approve(dInterestPool.address, INF, { from: acc2 })
      await dInterestPool.fundAll({ from: acc2 })

      // Wait 1 year
      await timePass(1)

      // Surplus should be zero, because the interest owed to funders should be deducted from surplus
      const surplusObj = await dInterestPool.surplus.call()
      assert(epsilonEq(0, surplusObj.surplusAmount), 'surplus not 0')

      // totalInterestOwedToFunders() should return the interest generated by the deposit
      const totalInterestOwedToFunders = await dInterestPool.totalInterestOwedToFunders.call()
      const interestExpected = depositAmount * (1 + IRMultiplier * INIT_INTEREST_RATE) * (INIT_INTEREST_RATE) // earned interest on deposit + interest
      assert(epsilonEq(totalInterestOwedToFunders, interestExpected), 'interest owed to funders not correct')
    })
  })

  describe('MPH tokenomics', () => {
    it('should mint correct MPH depositor reward', async () => {
      const depositAmount = 100 * STABLECOIN_PRECISION

      // acc0 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
      const blockNow = await latestBlockTimestamp()
      const acc0BeforeBalance = BigNumber(await mph.balanceOf(acc0))
      await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

      // wait for vest to finish
      await timePass(1 / 52) // 1 week
      await vesting.withdrawVested(acc0, 0, { from: acc0 })

      const expectedMPHReward = BigNumber(depositAmount).times(YEAR_IN_SEC).times(PoolDepositorRewardMintMultiplier).div(PRECISION)
      const actualMPHReward = BigNumber(await mph.balanceOf(acc0)).minus(acc0BeforeBalance)
      assert(epsilonEq(actualMPHReward, expectedMPHReward), 'MPH depositor reward incorrect')
    })

    it('should take back correct MPH depositor reward', async () => {
      const depositAmount = 100 * STABLECOIN_PRECISION

      // acc0 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
      const blockNow = await latestBlockTimestamp()
      const acc0BeforeBalance = BigNumber(await mph.balanceOf(acc0))
      await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

      // Wait 1 year
      await timePass(1)

      // Withdraw deposit 1
      await vesting.withdrawVested(acc0, 0, { from: acc0 })
      await dInterestPool.withdraw(1, 0, { from: acc0 })

      const expectedMPHReward = BigNumber(depositAmount).times(YEAR_IN_SEC).times(PoolDepositorRewardMintMultiplier).div(PRECISION).times(PRECISION - PoolDepositorRewardTakeBackMultiplier).div(PRECISION)
      const actualMPHReward = BigNumber(await mph.balanceOf(acc0)).minus(acc0BeforeBalance)
      assert(epsilonEq(actualMPHReward, expectedMPHReward), 'MPH depositor takeback amount incorrect')
    })

    it('should mint correct MPH funder reward', async () => {
      const depositAmount = 10 * STABLECOIN_PRECISION

      // acc0 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
      let blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc0 })

      // acc1 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc1 })
      blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc1 })

      // acc1 deposits stablecoin into the DInterest pool for 3 months
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc1 })
      blockNow = await latestBlockTimestamp()
      await dInterestPool.deposit(num2str(depositAmount), blockNow + 0.25 * YEAR_IN_SEC, { from: acc1 })

      // Wait 3 months
      await timePass(0.25)

      // Withdraw deposit 3
      await vesting.withdrawVested(acc1, 1, { from: acc1 })
      await dInterestPool.withdraw(3, 0, { from: acc1 })

      // Fund all deficit using acc2
      await stablecoin.approve(dInterestPool.address, INF, { from: acc2 })
      await dInterestPool.fundAll({ from: acc2 })

      // Wait 9 months
      await timePass(0.75)

      // acc0, acc1 withdraw deposits
      const acc2BeforeBalance = BigNumber(await mph.balanceOf(acc2))
      await vesting.withdrawVested(acc0, 0, { from: acc0 })
      await vesting.withdrawVested(acc1, 0, { from: acc1 })
      await dInterestPool.withdraw(1, 1, { from: acc0 })
      await dInterestPool.withdraw(2, 1, { from: acc1 })

      // Check interest earned by funder
      const actualMPHReward = BigNumber(await mph.balanceOf(acc2)).minus(acc2BeforeBalance)
      const expectedMPHReward = BigNumber(depositAmount * 2).times(0.75 * YEAR_IN_SEC).times(PoolFunderRewardMultiplier).div(PRECISION)
      assert(epsilonEq(actualMPHReward, expectedMPHReward), 'MPH funder reward amount incorrect')
    })

    it('should not increase depositor MPH balance if early withdraw', async () => {
      const depositAmount = 100 * STABLECOIN_PRECISION

      // acc0 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
      const blockNow = await latestBlockTimestamp()
      const acc0BeforeBalance = BigNumber(await mph.balanceOf(acc0))
      await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

      // acc0 withdraws early
      await timePass(1 / 52) // 1 week
      await vesting.withdrawVested(acc0, 0, { from: acc0 })
      await dInterestPool.earlyWithdraw(1, 0, { from: acc0 })

      const actualMPHReward = BigNumber(await mph.balanceOf(acc0)).minus(acc0BeforeBalance).div(PRECISION)
      assert(actualMPHReward.lte(0), 'early withdraw increased MPH balance')
    })

    it('should not increase attacker balances if deposit => buy bonds => immediately early withdraw', async () => {
      const depositAmount = 100 * STABLECOIN_PRECISION

      // acc0 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
      const blockNow = await latestBlockTimestamp()
      const acc0BeforeStablecoinBalance = BigNumber(await stablecoin.balanceOf(acc0))
      const acc0BeforeMPHBalance = BigNumber(await mph.balanceOf(acc0))
      await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

      // acc0 buys bonds
      await stablecoin.approve(dInterestPool.address, INF, { from: acc0 })
      await dInterestPool.fundAll({ from: acc0 })

      // acc0 withdraws early
      await timePass(1 / 52) // 1 week
      await vesting.withdrawVested(acc0, 0, { from: acc0 })
      await dInterestPool.earlyWithdraw(1, 1, { from: acc0 })

      const actualMPHReward = BigNumber(await mph.balanceOf(acc0)).minus(acc0BeforeMPHBalance)
      assert(actualMPHReward.lte(0), 'attack yielded MPH reward')

      const actualStablecoinReward = BigNumber(await stablecoin.balanceOf(acc0)).minus(acc0BeforeStablecoinBalance)
      const expectedMaxStablecoinReward = BigNumber(depositAmount).times(1 + IRMultiplier * INIT_INTEREST_RATE).times(INIT_INTEREST_RATE).times(1 / 52)
      assert(actualStablecoinReward.lte(expectedMaxStablecoinReward), 'attack yielded stablecoin reward')
    })

    it('should not increase attacker balances if deposit => buy bonds => wait a while => early withdraw', async () => {
      const depositAmount = 100 * STABLECOIN_PRECISION

      // acc0 deposits stablecoin into the DInterest pool for 1 year
      await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
      const blockNow = await latestBlockTimestamp()
      const acc0BeforeStablecoinBalance = BigNumber(await stablecoin.balanceOf(acc0))
      const acc0BeforeMPHBalance = BigNumber(await mph.balanceOf(acc0))
      await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

      // acc0 buys bonds
      await stablecoin.approve(dInterestPool.address, INF, { from: acc0 })
      await dInterestPool.fundAll({ from: acc0 })

      // Wait 3 months
      await timePass(0.25)

      // acc0 withdraws early
      await vesting.withdrawVested(acc0, 0, { from: acc0 })
      await dInterestPool.earlyWithdraw(1, 1, { from: acc0 })

      const actualMPHReward = BigNumber(await mph.balanceOf(acc0)).minus(acc0BeforeMPHBalance)
      assert(actualMPHReward.lte(0), 'attack yielded MPH reward')

      const actualStablecoinReward = BigNumber(await stablecoin.balanceOf(acc0)).minus(acc0BeforeStablecoinBalance)
      const expectedMaxStablecoinReward = BigNumber(depositAmount).times(1 + IRMultiplier * INIT_INTEREST_RATE).times(INIT_INTEREST_RATE).times(0.25)
      assert(actualStablecoinReward.lte(expectedMaxStablecoinReward), 'attack yielded stablecoin reward')
    })

    it('MPHMinter should not accept calls from random account', async () => {
      try {
        const depositAmount = 100 * STABLECOIN_PRECISION
        await mphMinter.mintDepositorReward(acc1, num2str(depositAmount), num2str(YEAR_IN_SEC), 0, { from: acc1 })
        assert.fail('Rando called mphMinter.mintDepositorReward()!!!')
      } catch { }

      try {
        const mintMPHAmount = 100 * PRECISION
        await mphMinter.takeBackDepositorReward(acc1, num2str(mintMPHAmount), true, { from: acc1 })
        assert.fail('Rando called mphMinter.takeBackDepositorReward()!!!')
      } catch { }

      try {
        const depositAmount = 100 * STABLECOIN_PRECISION
        const blockNow = await latestBlockTimestamp()
        await mphMinter.mintFunderReward(acc1, num2str(depositAmount), num2str(blockNow), num2str(blockNow + YEAR_IN_SEC), 0, false, { from: acc1 })
        assert.fail('Rando called mphMinter.mintFunderReward()!!!')
      } catch { }
    })

    it('owner can update MPH owner', async () => {
      await mphMinter.setMPHTokenOwner(devWallet, { from: acc0 })
      const newOwner = await mph.owner()
      assert.equal(newOwner, devWallet, 'MPH owner not updated')
    })
  })
})
