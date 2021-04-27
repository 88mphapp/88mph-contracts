const Base = require('../base')
const BigNumber = require('bignumber.js')
const { assert, artifacts } = require('hardhat')

const ZeroCouponBond = artifacts.require('ZeroCouponBond')

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
  const INIT_INTEREST_RATE_PER_SECOND = 0.1 / Base.YEAR_IN_SEC // 10% APY

  for (const moduleInfo of Base.moneyMarketModuleList) {
    const moneyMarketModule = moduleInfo.moduleGenerator()
    context(`Money market: ${moduleInfo.name}`, () => {
      beforeEach(async () => {
        stablecoin = await Base.ERC20Mock.new()

        // Mint stablecoin
        const mintAmount = 1000 * Base.STABLECOIN_PRECISION
        await stablecoin.mint(acc0, Base.num2str(mintAmount))
        await stablecoin.mint(acc1, Base.num2str(mintAmount))
        await stablecoin.mint(acc2, Base.num2str(mintAmount))

        // Initialize MPH
        mph = await Base.MPHToken.new()
        await mph.initialize()
        vesting = await Base.Vesting.new(mph.address)
        vesting02 = await Base.Vesting02.new()
        mphIssuanceModel = await Base.MPHIssuanceModel.new()
        await mphIssuanceModel.initialize(Base.DevRewardMultiplier, Base.GovRewardMultiplier)
        mphMinter = await Base.MPHMinter.new()
        await mphMinter.initialize(mph.address, govTreasury, devWallet, mphIssuanceModel.address, vesting.address, vesting02.address)
        await vesting02.initialize(mphMinter.address, mph.address, 'Vested MPH', 'veMPH')
        await mph.transferOwnership(mphMinter.address)
        await mphMinter.grantRole(Base.WHITELISTER_ROLE, acc0, { from: acc0 })

        // Set infinite MPH approval
        await mph.approve(mphMinter.address, Base.INF, { from: acc0 })
        await mph.approve(mphMinter.address, Base.INF, { from: acc1 })
        await mph.approve(mphMinter.address, Base.INF, { from: acc2 })

        // Deploy factory
        factory = await Base.Factory.new()

        // Deploy moneyMarket
        market = await moneyMarketModule.deployMoneyMarket(accounts, factory, stablecoin, govTreasury)

        // Initialize the NFTs
        const nftTemplate = await Base.NFT.new()
        const depositNFTReceipt = await factory.createNFT(nftTemplate.address, Base.DEFAULT_SALT, '88mph Deposit', '88mph-Deposit')
        depositNFT = await Base.factoryReceiptToContract(depositNFTReceipt, Base.NFT)
        const fundingMultitokenTemplate = await Base.FundingMultitoken.new()
        const fundingNFTReceipt = await factory.createFundingMultitoken(fundingMultitokenTemplate.address, Base.DEFAULT_SALT, stablecoin.address, 'https://api.88mph.app/funding-metadata/')
        fundingMultitoken = await Base.factoryReceiptToContract(fundingNFTReceipt, Base.FundingMultitoken)

        // Initialize the interest oracle
        const interestOracleTemplate = await Base.EMAOracle.new()
        const interestOracleReceipt = await factory.createEMAOracle(interestOracleTemplate.address, Base.DEFAULT_SALT, Base.num2str(INIT_INTEREST_RATE * Base.PRECISION / Base.YEAR_IN_SEC), Base.EMAUpdateInterval, Base.EMASmoothingFactor, Base.EMAAverageWindowInIntervals, market.address)
        interestOracle = await Base.factoryReceiptToContract(interestOracleReceipt, Base.EMAOracle)

        // Initialize the DInterest pool
        feeModel = await Base.PercentageFeeModel.new(govTreasury)
        interestModel = await Base.LinearDecayInterestModel.new(Base.num2str(Base.multiplierIntercept), Base.num2str(Base.multiplierSlope))
        const dInterestTemplate = await Base.DInterest.new()
        const dInterestReceipt = await factory.createDInterest(
          dInterestTemplate.address,
          Base.DEFAULT_SALT,
          Base.MaxDepositPeriod,
          Base.MinDepositAmount,
          market.address,
          stablecoin.address,
          feeModel.address,
          interestModel.address,
          interestOracle.address,
          depositNFT.address,
          fundingMultitoken.address,
          mphMinter.address
        )
        dInterestPool = await Base.factoryReceiptToContract(dInterestReceipt, Base.DInterest)

        // Set MPH minting multiplier for DInterest pool
        await mphMinter.grantRole(Base.WHITELISTED_POOL_ROLE, dInterestPool.address, { from: acc0 })
        await mphIssuanceModel.setPoolDepositorRewardMintMultiplier(dInterestPool.address, Base.PoolDepositorRewardMintMultiplier)
        await mphIssuanceModel.setPoolFunderRewardMultiplier(dInterestPool.address, Base.PoolFunderRewardMultiplier)
        await mphIssuanceModel.setPoolFunderRewardVestPeriod(dInterestPool.address, Base.PoolFunderRewardVestPeriod)

        // Transfer the ownership of the money market to the DInterest pool
        await market.transferOwnership(dInterestPool.address)

        // Transfer NFT ownerships to the DInterest pool
        await depositNFT.transferOwnership(dInterestPool.address)
        await fundingMultitoken.grantRole(Base.MINTER_BURNER_ROLE, dInterestPool.address)
        await fundingMultitoken.grantRole(Base.DIVIDEND_ROLE, dInterestPool.address)

        // Deploy ZeroCouponBond
        const zeroCouponBondTemplate = await ZeroCouponBond.new()
        const blockNow = await Base.latestBlockTimestamp()
        const zeroCouponBondAddress = await factory.predictAddress(zeroCouponBondTemplate.address, Base.DEFAULT_SALT)
        await stablecoin.approve(zeroCouponBondAddress, Base.num2str(Base.MinDepositAmount))
        const zcbReceipt = await factory.createZeroCouponBond(
          zeroCouponBondTemplate.address,
          Base.DEFAULT_SALT,
          dInterestPool.address,
          Base.num2str(blockNow + 2 * Base.YEAR_IN_SEC),
          Base.num2str(Base.MinDepositAmount),
          '88mph Zero Coupon Bond',
          'MPHZCB-Jan-2023',
          { from: acc0 }
        )
        zeroCouponBond = await Base.factoryReceiptToContract(zcbReceipt, ZeroCouponBond)
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
