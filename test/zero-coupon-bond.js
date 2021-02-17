// Libraries
const BigNumber = require('bignumber.js')

// Contract artifacts
const DInterest = artifacts.require('DInterest')
const PercentageFeeModel = artifacts.require('PercentageFeeModel')
const LinearInterestModel = artifacts.require('LinearInterestModel')
const NFT = artifacts.require('NFT')
const NFTFactory = artifacts.require('NFTFactory')
const MPHToken = artifacts.require('MPHToken')
const MPHMinter = artifacts.require('MPHMinter')
const ERC20Mock = artifacts.require('ERC20Mock')
const Rewards = artifacts.require('Rewards')
const EMAOracle = artifacts.require('EMAOracle')
const MPHIssuanceModel = artifacts.require('MPHIssuanceModel01')
const Vesting = artifacts.require('Vesting')

const VaultMock = artifacts.require('VaultMock')
const HarvestStakingMock = artifacts.require('HarvestStakingMock')
const HarvestMarket = artifacts.require('HarvestMarket')

const FractionalDeposit = artifacts.require('FractionalDeposit')
const FractionalDepositFactory = artifacts.require('FractionalDepositFactory')
const ZeroCouponBond = artifacts.require('ZeroCouponBond')
const ZeroCouponBondFactory = artifacts.require('ZeroCouponBondFactory')

// Constants
const PRECISION = 1e18
const STABLECOIN_PRECISION = 1e6
const YEAR_IN_SEC = 31556952 // Number of seconds in a year
const IRMultiplier = BigNumber(0.75 * 1e18).integerValue().toFixed() // Minimum safe avg interest rate multiplier
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

// Converts a JS number into a string that doesn't use scientific notation
function num2str(num) {
  return BigNumber(num).integerValue().toFixed()
}

function epsilonEq(curr, prev, ep) {
  const _epsilon = ep || epsilon
  return BigNumber(curr).eq(prev) ||
    (!BigNumber(prev).isZero() && BigNumber(curr).minus(prev).div(prev).abs().lt(_epsilon)) ||
    (!BigNumber(curr).isZero() && BigNumber(prev).minus(curr).div(curr).abs().lt(_epsilon))
}

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
  let vault
  let farmToken
  let harvestStaking
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
  let fractionalDepositFactory
  let zeroCouponBondFactory
  let nftFactory

  // Constants
  const INIT_INTEREST_RATE = 0.1 // 10% APY
  const depositAmount = 100 * STABLECOIN_PRECISION

  const timePass = async (timeInYears) => {
    await timeTravel(timeInYears * YEAR_IN_SEC)
    await stablecoin.mint(vault.address, num2str(BigNumber(await stablecoin.balanceOf(vault.address)).times(INIT_INTEREST_RATE).times(timeInYears)))
  }

  beforeEach(async function () {
    // Initialize mock stablecoin and vault
    stablecoin = await ERC20Mock.new()
    vault = await VaultMock.new(stablecoin.address)

    // Initialize FARM rewards
    farmToken = await ERC20Mock.new()
    const farmRewards = 1000 * STABLECOIN_PRECISION
    harvestStaking = await HarvestStakingMock.new(vault.address, farmToken.address, Math.floor(Date.now() / 1e3))
    await farmToken.mint(harvestStaking.address, num2str(farmRewards))
    await harvestStaking.setRewardDistribution(acc0, true)
    await harvestStaking.notifyRewardAmount(num2str(farmRewards), { from: acc0 })

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
    market = await HarvestMarket.new(vault.address, rewards.address, harvestStaking.address, stablecoin.address)

    // Initialize the NFTs
    const nftTemplate = await NFT.new()
    nftFactory = await NFTFactory.new(nftTemplate.address)
    const depositNFTReceipt = await nftFactory.createClone('88mph Deposit', '88mph-Deposit')
    depositNFT = await NFT.at(depositNFTReceipt.logs[0].args._clone)
    const fundingNFTReceipt = await nftFactory.createClone('88mph Funding', '88mph-Funding')
    fundingNFT = await NFT.at(fundingNFTReceipt.logs[0].args._clone)

    // Initialize the interest oracle
    interestOracle = await EMAOracle.new(num2str(INIT_INTEREST_RATE * PRECISION / YEAR_IN_SEC), EMAUpdateInterval, EMASmoothingFactor, EMAAverageWindowInIntervals, market.address)

    // Initialize the DInterest pool
    feeModel = await PercentageFeeModel.new(rewards.address)
    interestModel = await LinearInterestModel.new(IRMultiplier)
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

    // Deploy FractionalDepositFactory
    const fractionalDepositTemplate = await FractionalDeposit.new()
    fractionalDepositFactory = await FractionalDepositFactory.new(fractionalDepositTemplate.address, mph.address)
    await mph.approve(fractionalDepositFactory.address, INF, { from: acc0 })

    // acc0 deposits stablecoin into the DInterest pool for 1 year
    await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 })
    const blockNow = await latestBlockTimestamp()
    await dInterestPool.deposit(num2str(depositAmount), num2str(blockNow + YEAR_IN_SEC), { from: acc0 })

    // withdraw vested MPH reward after 7 days
    await timePass(1 / 52)
    await vesting.withdrawVested(acc0, 0, { from: acc0 })

    // Deploy ZeroCouponBondFactory
    const zeroCouponBondTemplate = await ZeroCouponBond.new()
    zeroCouponBondFactory = await ZeroCouponBondFactory.new(zeroCouponBondTemplate.address, fractionalDepositFactory.address)
  })

  it('create zero coupon bond', async () => {
    const blockNow = await latestBlockTimestamp()
    await zeroCouponBondFactory.createZeroCouponBond(
      dInterestPool.address,
      num2str(blockNow + 2 * YEAR_IN_SEC),
      '88mph Zero Coupon Bond',
      'MPHZCB-Jan-2023',
      { from: acc0 }
    )
  })

  it('create zero coupon bond from NFT and redeem', async () => {
    // create ZCB
    const blockNow = await latestBlockTimestamp()
    const zcbReceipt = await zeroCouponBondFactory.createZeroCouponBond(
      dInterestPool.address,
      num2str(blockNow + 2 * YEAR_IN_SEC),
      '88mph Zero Coupon Bond',
      'MPHZCB-Jan-2023',
      { from: acc0 }
    )
    const zcbAddress = zcbReceipt.logs[0].args._clone
    const zcb = await ZeroCouponBond.at(zcbAddress)

    // mint ZCB
    await depositNFT.approve(zcbAddress, 1)
    await mph.approve(zcbAddress, INF)
    const mintReceipt = await zcb.mintWithDepositNFT(1, '88mph Fractional Deposit', 'MPHFD-Jan-2022')
    const fractionalDepositAddress = mintReceipt.logs[mintReceipt.logs.length - 1].args.fractionalDepositAddress
    const fractionalDeposit = await FractionalDeposit.at(fractionalDepositAddress)
    const fractionalDepositBalance = await fractionalDeposit.balanceOf(zcbAddress)

    // wait 2 years
    await timePass(2)

    // redeem fractional deposit shares
    await zcb.redeemFractionalDepositShares(fractionalDepositAddress, 0)

    // check balances
    assert(epsilonEq(await stablecoin.balanceOf(zcbAddress), fractionalDepositBalance), 'stablecoins not withdrawn to zero coupon bonds contract')

    // redeem stablecoin
    const beforeStablecoinBalance = await stablecoin.balanceOf(acc0)
    await zcb.redeemStablecoin(await zcb.balanceOf(acc0))
    const afterStablecoinBalance = await stablecoin.balanceOf(acc0)

    // check balances
    const actualMPHReward = await mph.balanceOf(acc0)
    const expectedMPHReward = BigNumber(PoolDepositorRewardMintMultiplier).times(depositAmount).div(PRECISION).times(YEAR_IN_SEC).times(BigNumber(PRECISION).minus(PoolDepositorRewardTakeBackMultiplier)).div(PRECISION)
    assert(epsilonEq(actualMPHReward, expectedMPHReward), 'MPH reward amount incorrect')
    assert(epsilonEq(afterStablecoinBalance.sub(beforeStablecoinBalance), fractionalDepositBalance), 'stablecoins not credited to acc0')
    assert(BigNumber(await zcb.balanceOf(acc0)).div(STABLECOIN_PRECISION).lt(epsilon), 'zero coupon bonds not burned from acc0')
    assert(BigNumber(await fractionalDeposit.balanceOf(zcbAddress)).div(STABLECOIN_PRECISION).lt(epsilon), 'fractional deposit not burned from zero coupon bonds contract')
  })

  it('should not be able to mint using deposit that matures after the zero coupon bond', async () => {
    // create ZCB that matures in 6 months (earlier than the deposit)
    const blockNow = await latestBlockTimestamp()
    const zcbReceipt = await zeroCouponBondFactory.createZeroCouponBond(
      dInterestPool.address,
      num2str(blockNow + 0.5 * YEAR_IN_SEC),
      '88mph Zero Coupon Bond',
      'MPHZCB',
      { from: acc0 }
    )
    const zcbAddress = zcbReceipt.logs[0].args._clone
    const zcb = await ZeroCouponBond.at(zcbAddress)

    // mint ZCB
    await depositNFT.approve(zcbAddress, 1)
    await mph.approve(zcbAddress, INF)
    try {
      await zcb.mintWithDepositNFT(1, '88mph Fractional Deposit', 'MPHFD-Jan-2022')
      assert.fail('minted with deposit that matures after the zero coupon bond')
    } catch (error) {
      if (error.message === 'minted with deposit that matures after the zero coupon bond') {
        assert.fail('minted with deposit that matures after the zero coupon bond')
      }
    }
  })
})
