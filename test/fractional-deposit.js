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
const HarvestStakingMock = artifacts.require('HarvestStakingMock')
const HarvestMarket = artifacts.require('HarvestMarket')

const FractionalDeposit = artifacts.require('FractionalDeposit')
const FractionalDepositFactory = artifacts.require('FractionalDepositFactory')

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

// Tests
contract('FractionalDeposit', accounts => {
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
    depositNFT = await NFT.new('88mph Deposit', '88mph-Deposit')
    fundingNFT = await NFT.new('88mph Funding', '88mph-Funding')

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
  })

  it('create fractional deposit', async () => {
    // create fractional deposit
    await depositNFT.setApprovalForAll(fractionalDepositFactory.address, true, { from: acc0 })
    await fractionalDepositFactory.createFractionalDeposit(
      dInterestPool.address,
      1,
      '88mph Fractional Deposit',
      'MPHFD-01',
      { from: acc0 }
    )
  })

  it('withdraw deposit after maturation', async () => {
    // create fractional deposit
    await depositNFT.setApprovalForAll(fractionalDepositFactory.address, true, { from: acc0 })
    const receipt = await fractionalDepositFactory.createFractionalDeposit(
      dInterestPool.address,
      1,
      '88mph Fractional Deposit',
      'MPHFD-01',
      { from: acc0 }
    )
    const fractionalDepositAddress = receipt.logs[0].args._clone
    const fractionalDeposit = await FractionalDeposit.at(fractionalDepositAddress)

    // wait for 1 year
    await timePass(1)

    // withdraw deposit
    await mph.approve(fractionalDeposit.address, INF, { from: acc0 })
    await fractionalDeposit.withdrawDeposit(0, { from: acc0 })
  })

  describe('redeem with direct withdrawal', () => {
    let fractionalDeposit

    beforeEach(async () => {
      // create fractional deposit
      await depositNFT.setApprovalForAll(fractionalDepositFactory.address, true, { from: acc0 })
      const receipt = await fractionalDepositFactory.createFractionalDeposit(
        dInterestPool.address,
        1,
        '88mph Fractional Deposit',
        'MPHFD-01',
        { from: acc0 }
      )
      const fractionalDepositAddress = receipt.logs[0].args._clone
      fractionalDeposit = await FractionalDeposit.at(fractionalDepositAddress)

      // wait for 1 year
      await timePass(1)

      // withdraw deposit
      await fractionalDeposit.withdrawDeposit(0, { from: acc0 })
    })

    it('redeem share', async () => {
      const shareTotalSupply = BigNumber(await fractionalDeposit.totalSupply())
      const depositBalance = shareTotalSupply

      // transfer 50% of shares to acc1, 30% to acc2
      await fractionalDeposit.transfer(acc1, num2str(shareTotalSupply.times(0.5)), { from: acc0 })
      await fractionalDeposit.transfer(acc2, num2str(shareTotalSupply.times(0.3)), { from: acc0 })

      // redeem shares
      const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
      const acc1BeforeBalance = BigNumber(await stablecoin.balanceOf(acc1))
      const acc2BeforeBalance = BigNumber(await stablecoin.balanceOf(acc2))
      await fractionalDeposit.redeemShares(await fractionalDeposit.balanceOf(acc0), 0, { from: acc0 })
      await fractionalDeposit.redeemShares(await fractionalDeposit.balanceOf(acc1), 0, { from: acc1 })
      await fractionalDeposit.redeemShares(await fractionalDeposit.balanceOf(acc2), 0, { from: acc2 })
      const acc0AfterBalance = BigNumber(await stablecoin.balanceOf(acc0))
      const acc1AfterBalance = BigNumber(await stablecoin.balanceOf(acc1))
      const acc2AfterBalance = BigNumber(await stablecoin.balanceOf(acc2))

      // verify stablecoin balances
      assert(epsilonEq(depositBalance.times(0.2), acc0AfterBalance.minus(acc0BeforeBalance)), 'acc0 redeem amount incorrect')
      assert(epsilonEq(depositBalance.times(0.5), acc1AfterBalance.minus(acc1BeforeBalance)), 'acc1 redeem amount incorrect')
      assert(epsilonEq(depositBalance.times(0.3), acc2AfterBalance.minus(acc2BeforeBalance)), 'acc2 redeem amount incorrect')
    })

    it('transfer NFT to creator', async () => {
      await fractionalDeposit.transferNFTToOwner({ from: acc0 })

      // verify NFT ownership
      const nftOwner = await depositNFT.ownerOf(1)
      assert.equal(nftOwner, acc0, 'acc0 not owner of deposit NFT')
    })
  })

  describe('redeem without direct withdrawal', () => {
    let fractionalDeposit

    beforeEach(async () => {
      // create fractional deposit
      await depositNFT.setApprovalForAll(fractionalDepositFactory.address, true, { from: acc0 })
      const receipt = await fractionalDepositFactory.createFractionalDeposit(
        dInterestPool.address,
        1,
        '88mph Fractional Deposit',
        'MPHFD-01',
        { from: acc0 }
      )
      const fractionalDepositAddress = receipt.logs[0].args._clone
      fractionalDeposit = await FractionalDeposit.at(fractionalDepositAddress)

      // wait for 1 year
      await timePass(1)
    })

    it('redeem share', async () => {
      const shareTotalSupply = BigNumber(await fractionalDeposit.totalSupply())
      const depositBalance = shareTotalSupply

      // transfer 50% of shares to acc1, 30% to acc2
      await fractionalDeposit.transfer(acc1, num2str(shareTotalSupply.times(0.5)), { from: acc0 })
      await fractionalDeposit.transfer(acc2, num2str(shareTotalSupply.times(0.3)), { from: acc0 })

      // redeem shares
      const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
      const acc1BeforeBalance = BigNumber(await stablecoin.balanceOf(acc1))
      const acc2BeforeBalance = BigNumber(await stablecoin.balanceOf(acc2))
      await fractionalDeposit.redeemShares(await fractionalDeposit.balanceOf(acc0), 0, { from: acc0 })
      await fractionalDeposit.redeemShares(await fractionalDeposit.balanceOf(acc1), 0, { from: acc1 })
      await fractionalDeposit.redeemShares(await fractionalDeposit.balanceOf(acc2), 0, { from: acc2 })
      const acc0AfterBalance = BigNumber(await stablecoin.balanceOf(acc0))
      const acc1AfterBalance = BigNumber(await stablecoin.balanceOf(acc1))
      const acc2AfterBalance = BigNumber(await stablecoin.balanceOf(acc2))

      // verify stablecoin balances
      assert(epsilonEq(depositBalance.times(0.2), acc0AfterBalance.minus(acc0BeforeBalance)), 'acc0 redeem amount incorrect')
      assert(epsilonEq(depositBalance.times(0.5), acc1AfterBalance.minus(acc1BeforeBalance)), 'acc1 redeem amount incorrect')
      assert(epsilonEq(depositBalance.times(0.3), acc2AfterBalance.minus(acc2BeforeBalance)), 'acc2 redeem amount incorrect')
    })
  })
})
