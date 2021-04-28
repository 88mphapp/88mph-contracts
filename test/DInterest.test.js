const Base = require('./base')
const BigNumber = require('bignumber.js')
const { assert } = require('hardhat')

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
  let mphIssuanceModel
  let vesting
  let vesting02
  let factory

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
        const fundingNFTReceipt = await factory.createFundingMultitoken(fundingMultitokenTemplate.address, Base.DEFAULT_SALT, [stablecoin.address, mph.address], 'https://api.88mph.app/funding-metadata/')
        fundingMultitoken = await Base.factoryReceiptToContract(fundingNFTReceipt, Base.FundingMultitoken)

        // Initialize the interest oracle
        const interestOracleTemplate = await Base.EMAOracle.new()
        const interestOracleReceipt = await factory.createEMAOracle(interestOracleTemplate.address, Base.DEFAULT_SALT, Base.num2str(INIT_INTEREST_RATE * Base.PRECISION / Base.YEAR_IN_SEC), Base.EMAUpdateInterval, Base.EMASmoothingFactor, Base.EMAAverageWindowInIntervals, market.address)
        interestOracle = await Base.factoryReceiptToContract(interestOracleReceipt, Base.EMAOracle)

        // Initialize the DInterest pool
        feeModel = await Base.PercentageFeeModel.new(govTreasury, Base.interestFee, Base.earlyWithdrawFee)
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
        await fundingMultitoken.grantRole(Base.DIVIDEND_ROLE, mphMinter.address)
      })

      describe('deposit', () => {
        context('happy path', () => {
          it('should update global variables correctly', async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + Base.YEAR_IN_SEC), { from: acc0 })

            // Calculate interest amount
            const expectedInterest = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, true)

            // Verify totalDeposit
            const totalDeposit = BigNumber(await dInterestPool.totalDeposit())
            Base.assertEpsilonEq(totalDeposit, depositAmount, 'totalDeposit not updated after acc0 deposited')

            // Verify totalInterestOwed
            const totalInterestOwed = BigNumber(await dInterestPool.totalInterestOwed())
            Base.assertEpsilonEq(totalInterestOwed, expectedInterest, 'totalInterestOwed not updated after acc0 deposited')

            // Verify totalFeeOwed
            const totalFeeOwed = BigNumber(await dInterestPool.totalFeeOwed())
            const expectedTotalFeeOwed = totalInterestOwed.plus(totalFeeOwed).minus(Base.applyFee(totalInterestOwed.plus(totalFeeOwed)))
            Base.assertEpsilonEq(totalFeeOwed, expectedTotalFeeOwed, 'totalFeeOwed not updated after acc0 deposited')
          })

          it('should transfer funds correctly', async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
            const dInterestPoolBeforeBalance = BigNumber(await market.totalValue.call())
            await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + Base.YEAR_IN_SEC), { from: acc0 })

            const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
            const dInterestPoolCurrentBalance = BigNumber(await market.totalValue.call())

            // Verify stablecoin transferred out of account
            Base.assertEpsilonEq(acc0BeforeBalance.minus(acc0CurrentBalance), depositAmount, 'stablecoin not transferred out of acc0')

            // Verify stablecoin transferred into money market
            Base.assertEpsilonEq(dInterestPoolCurrentBalance.minus(dInterestPoolBeforeBalance), depositAmount, 'stablecoin not transferred into money market')
          })
        })

        context('edge cases', () => {
          it('should fail with very short deposit period', async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION

            // acc0 deposits for 1 second
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            try {
              await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + 1), { from: acc0 })
              assert.fail()
            } catch (error) { }
          })

          it('should fail with greater than maximum deposit period', async function () {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION

            // acc0 deposits for 10 years
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            try {
              await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + 10 * Base.YEAR_IN_SEC), { from: acc0 })
              assert.fail()
            } catch (error) { }
          })

          it('should fail with less than minimum deposit amount', async function () {
            const depositAmount = 0.001 * Base.STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            try {
              await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + Base.YEAR_IN_SEC), { from: acc0 })
              assert.fail()
            } catch (error) { }
          })
        })
      })

      describe('topupDeposit', () => {
        context('happy path', () => {
          it('should update global variables correctly', async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + Base.YEAR_IN_SEC), { from: acc0 })

            // topup
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            await dInterestPool.topupDeposit(1, Base.num2str(depositAmount), { from: acc0 })

            // Calculate interest amount
            const expectedInterest = Base.calcInterestAmount(2 * depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, true)

            // Verify totalDeposit
            const totalDeposit = BigNumber(await dInterestPool.totalDeposit())
            Base.assertEpsilonEq(totalDeposit, 2 * depositAmount, 'totalDeposit not updated after acc0 deposited')

            // Verify totalInterestOwed
            const totalInterestOwed = BigNumber(await dInterestPool.totalInterestOwed())
            Base.assertEpsilonEq(totalInterestOwed, expectedInterest, 'totalInterestOwed not updated after acc0 deposited')

            // Verify totalFeeOwed
            const totalFeeOwed = BigNumber(await dInterestPool.totalFeeOwed())
            const expectedTotalFeeOwed = totalInterestOwed.plus(totalFeeOwed).minus(Base.applyFee(totalInterestOwed.plus(totalFeeOwed)))
            Base.assertEpsilonEq(totalFeeOwed, expectedTotalFeeOwed, 'totalFeeOwed not updated after acc0 deposited')
          })

          it('should transfer funds correctly', async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + Base.YEAR_IN_SEC), { from: acc0 })

            // topup
            const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
            const dInterestPoolBeforeBalance = BigNumber(await market.totalValue.call())
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            await dInterestPool.topupDeposit(1, Base.num2str(depositAmount), { from: acc0 })

            const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
            const dInterestPoolCurrentBalance = BigNumber(await market.totalValue.call())

            // Verify stablecoin transferred out of account
            Base.assertEpsilonEq(acc0BeforeBalance.minus(acc0CurrentBalance), depositAmount, 'stablecoin not transferred out of acc0')

            // Verify stablecoin transferred into money market
            Base.assertEpsilonEq(dInterestPoolCurrentBalance.minus(dInterestPoolBeforeBalance), depositAmount, 'stablecoin not transferred into money market')
          })

          it('should withdraw correctly', async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + Base.YEAR_IN_SEC), { from: acc0 })

            // topup
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            await dInterestPool.topupDeposit(1, Base.num2str(depositAmount), { from: acc0 })

            // wait 1 year
            await moneyMarketModule.timePass(1)

            // withdraw
            const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
            const dInterestPoolBeforeBalance = BigNumber(await market.totalValue.call())
            await dInterestPool.withdraw(1, Base.INF, false, { from: acc0 })
            const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
            const dInterestPoolCurrentBalance = BigNumber(await market.totalValue.call())

            // Verify totalDeposit
            const totalDeposit = BigNumber(await dInterestPool.totalDeposit())
            Base.assertEpsilonEq(totalDeposit, 0, 'totalDeposit not updated after acc0 withdrew')

            // Verify totalInterestOwed
            const totalInterestOwed = BigNumber(await dInterestPool.totalInterestOwed())
            Base.assertEpsilonEq(totalInterestOwed, 0, 'totalInterestOwed not updated after acc0 withdrew')

            // Verify totalFeeOwed
            const totalFeeOwed = BigNumber(await dInterestPool.totalFeeOwed())
            Base.assertEpsilonEq(totalFeeOwed, 0, 'totalFeeOwed not updated after acc0 withdrew')

            // Verify stablecoin transferred to account
            const expectedInterest = Base.calcInterestAmount(2 * depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, true)
            const expectedWithdrawAmount = expectedInterest.plus(2 * depositAmount)
            Base.assertEpsilonEq(acc0CurrentBalance.minus(acc0BeforeBalance), expectedWithdrawAmount, 'stablecoin not transferred to acc0')

            // Verify stablecoin transferred from money market
            const expectedInterestPlusFee = Base.calcInterestAmount(2 * depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, false)
            const expectedPoolValueChange = expectedInterestPlusFee.plus(2 * depositAmount)
            Base.assertEpsilonEq(dInterestPoolBeforeBalance.minus(dInterestPoolCurrentBalance), expectedPoolValueChange, 'stablecoin not transferred from money market')
          })
        })

        context('edge cases', () => {

        })
      })

      describe('rolloverDeposit', () => {
        context('happy path', () => {
          const depositAmount = 100 * Base.STABLECOIN_PRECISION

          beforeEach(async () => {
            // acc0 deposits
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + Base.YEAR_IN_SEC), { from: acc0 })
          })

          it('should create a new deposit with new maturationTimestamp and deposit amount increased', async function () {
            // Wait 1 year (maturation time)
            await moneyMarketModule.timePass(1)
            const blockNow = await Base.latestBlockTimestamp()

            // calculate first deposit withdrawn value
            const valueOfFirstDepositAfterMaturation = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, true).plus(depositAmount)
            const valueOfRolloverDepositAfterMaturation = Base.calcInterestAmount(valueOfFirstDepositAfterMaturation, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, true).plus(valueOfFirstDepositAfterMaturation)
            await dInterestPool.rolloverDeposit(Base.num2str(1), Base.num2str(blockNow + Base.YEAR_IN_SEC), { from: acc0 })

            const deposit1 = await dInterestPool.getDeposit(Base.num2str(1))
            const deposit2 = await dInterestPool.getDeposit(Base.num2str(2))
            assert.equal(deposit1.virtualTokenTotalSupply, 0, 'old deposit value must be equals 0')
            assert.equal(deposit2.maturationTimestamp, blockNow + Base.YEAR_IN_SEC, 'new deposit maturation time is not correct')
            Base.assertEpsilonEq(deposit2.virtualTokenTotalSupply, valueOfRolloverDepositAfterMaturation, 'rollover deposit do not have the correct token number')
          })
        })

        context('edge cases', () => {

        })
      })

      describe('withdraw', () => {
        context('withdraw after maturation', () => {
          const depositAmount = 100 * Base.STABLECOIN_PRECISION

          beforeEach(async () => {
            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + Base.YEAR_IN_SEC), { from: acc0 })

            // Wait 1 year
            await moneyMarketModule.timePass(1)
          })

          context('full withdrawal', () => {
            it('should update global variables correctly', async () => {
              // Withdraw
              await dInterestPool.withdraw(1, Base.INF, false, { from: acc0 })

              // Verify totalDeposit
              const totalDeposit = BigNumber(await dInterestPool.totalDeposit())
              Base.assertEpsilonEq(totalDeposit, 0, 'totalDeposit incorrect')

              // Verify totalInterestOwed
              const totalInterestOwed = BigNumber(await dInterestPool.totalInterestOwed())
              Base.assertEpsilonEq(totalInterestOwed, 0, 'totalInterestOwed incorrect')

              // Verify totalFeeOwed
              const totalFeeOwed = BigNumber(await dInterestPool.totalFeeOwed())
              Base.assertEpsilonEq(totalFeeOwed, 0, 'totalFeeOwed incorrect')
            })

            it('should transfer funds correctly', async function () {
              const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolBeforeBalance = BigNumber(await market.totalValue.call())

              // Withdraw
              await dInterestPool.withdraw(1, Base.INF, false, { from: acc0 })

              const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolCurrentBalance = BigNumber(await market.totalValue.call())

              // Verify stablecoin transferred into account
              const expectedInterest = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, true)
              const expectedWithdrawAmount = expectedInterest.plus(depositAmount)
              Base.assertEpsilonEq(acc0CurrentBalance.minus(acc0BeforeBalance), expectedWithdrawAmount, 'stablecoin not transferred into acc0')

              // Verify stablecoin transferred into money market
              const actualPoolValueChange = dInterestPoolBeforeBalance.minus(dInterestPoolCurrentBalance)
              const expectedPoolValueChange = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, false).plus(depositAmount)
              Base.assertEpsilonEq(actualPoolValueChange, expectedPoolValueChange, 'stablecoin not transferred out of money market')
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
              await dInterestPool.withdraw(1, Base.num2str(withdrawVirtualTokenAmount), false, { from: acc0 })

              // Verify totalDeposit
              const totalDeposit = BigNumber(await dInterestPool.totalDeposit())
              Base.assertEpsilonEq(totalDeposit, depositAmount * (1 - withdrawProportion), 'totalDeposit incorrect')

              // Verify totalInterestOwed
              const totalInterestOwed = BigNumber(await dInterestPool.totalInterestOwed())
              const expectedInterest = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, true).times(1 - withdrawProportion)
              Base.assertEpsilonEq(totalInterestOwed, expectedInterest, 'totalInterestOwed incorrect')

              // Verify totalFeeOwed
              const totalFeeOwed = BigNumber(await dInterestPool.totalFeeOwed())
              const expectedTotalFeeOwed = Base.calcFeeAmount(Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, false)).times(1 - withdrawProportion)
              Base.assertEpsilonEq(totalFeeOwed, expectedTotalFeeOwed, 'totalFeeOwed incorrect')
            })

            it('should transfer funds correctly', async function () {
              const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolBeforeBalance = BigNumber(await market.totalValue.call())

              // Withdraw
              await dInterestPool.withdraw(1, Base.num2str(withdrawVirtualTokenAmount), false, { from: acc0 })

              const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolCurrentBalance = BigNumber(await market.totalValue.call())

              // Verify stablecoin transferred into account
              const expectedInterest = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, true)
              const expectedWithdrawAmount = expectedInterest.plus(depositAmount).times(withdrawProportion)
              Base.assertEpsilonEq(acc0CurrentBalance.minus(acc0BeforeBalance), expectedWithdrawAmount, 'stablecoin not transferred into acc0')

              // Verify stablecoin transferred into money market
              const actualPoolValueChange = dInterestPoolBeforeBalance.minus(dInterestPoolCurrentBalance)
              const expectedPoolValueChange = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, false).plus(depositAmount).times(withdrawProportion)
              Base.assertEpsilonEq(actualPoolValueChange, expectedPoolValueChange, 'stablecoin not transferred out of money market')
            })
          })
        })

        context('withdraw before maturation', () => {
          const depositAmount = 100 * Base.STABLECOIN_PRECISION

          beforeEach(async () => {
            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + Base.YEAR_IN_SEC), { from: acc0 })

            // Wait 0.5 year
            await moneyMarketModule.timePass(0.5)
          })

          context('full withdrawal', () => {
            it('should update global variables correctly', async () => {
              // Withdraw
              await dInterestPool.withdraw(1, Base.INF, true, { from: acc0 })

              // Verify totalDeposit
              const totalDeposit = BigNumber(await dInterestPool.totalDeposit())
              Base.assertEpsilonEq(totalDeposit, 0, 'totalDeposit incorrect')

              // Verify totalInterestOwed
              const totalInterestOwed = BigNumber(await dInterestPool.totalInterestOwed())
              Base.assertEpsilonEq(totalInterestOwed, 0, 'totalInterestOwed incorrect')

              // Verify totalFeeOwed
              const totalFeeOwed = BigNumber(await dInterestPool.totalFeeOwed())
              Base.assertEpsilonEq(totalFeeOwed, 0, 'totalFeeOwed incorrect')
            })

            it('should transfer funds correctly', async () => {
              const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolBeforeBalance = BigNumber(await market.totalValue.call())

              // Withdraw
              await dInterestPool.withdraw(1, Base.INF, true, { from: acc0 })

              const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolCurrentBalance = BigNumber(await market.totalValue.call())

              // Verify stablecoin transferred into account
              const expectedReceiveStablecoinAmount = Base.applyEarlyWithdrawFee(depositAmount)
              Base.assertEpsilonEq(acc0CurrentBalance.minus(acc0BeforeBalance), expectedReceiveStablecoinAmount, 'stablecoin not transferred into acc0')

              // Verify stablecoin transferred from money market
              const actualPoolValueChange = dInterestPoolBeforeBalance.minus(dInterestPoolCurrentBalance)
              Base.assertEpsilonEq(actualPoolValueChange, depositAmount, 'stablecoin not transferred out of money market')
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
              await dInterestPool.withdraw(1, Base.num2str(withdrawVirtualTokenAmount), true, { from: acc0 })

              // Verify totalDeposit
              const totalDeposit = BigNumber(await dInterestPool.totalDeposit())
              Base.assertEpsilonEq(totalDeposit, depositAmount * (1 - withdrawProportion), 'totalDeposit incorrect')

              // Verify totalInterestOwed
              const totalInterestOwed = BigNumber(await dInterestPool.totalInterestOwed())
              const expectedInterest = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, true).times(1 - withdrawProportion)
              Base.assertEpsilonEq(totalInterestOwed, expectedInterest, 'totalInterestOwed incorrect')

              // Verify totalFeeOwed
              const totalFeeOwed = BigNumber(await dInterestPool.totalFeeOwed())
              const expectedTotalFeeOwed = Base.calcFeeAmount(Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, false)).times(1 - withdrawProportion)
              Base.assertEpsilonEq(totalFeeOwed, expectedTotalFeeOwed, 'totalFeeOwed incorrect')
            })

            it('should transfer funds correctly', async function () {
              const acc0BeforeBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolBeforeBalance = BigNumber(await market.totalValue.call())

              // Withdraw
              await dInterestPool.withdraw(1, Base.num2str(withdrawVirtualTokenAmount), true, { from: acc0 })

              const acc0CurrentBalance = BigNumber(await stablecoin.balanceOf(acc0))
              const dInterestPoolCurrentBalance = BigNumber(await market.totalValue.call())

              // Verify stablecoin transferred into account
              const expectedWithdrawAmount = Base.applyEarlyWithdrawFee(BigNumber(depositAmount).times(withdrawProportion))
              Base.assertEpsilonEq(acc0CurrentBalance.minus(acc0BeforeBalance), expectedWithdrawAmount, 'stablecoin not transferred into acc0')

              // Verify stablecoin transferred into money market
              const actualPoolValueChange = dInterestPoolBeforeBalance.minus(dInterestPoolCurrentBalance)
              const expectedPoolValueChange = BigNumber(depositAmount).times(withdrawProportion)
              Base.assertEpsilonEq(actualPoolValueChange, expectedPoolValueChange, 'stablecoin not transferred out of money market')
            })
          })
        })

        context('complex examples', () => {
          it('two deposits with overlap', async () => {
            const depositAmount = 10 * Base.STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            let blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), blockNow + Base.YEAR_IN_SEC, { from: acc0 })

            // Wait 0.5 year
            await moneyMarketModule.timePass(0.5)

            // acc1 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc1 })
            blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), blockNow + Base.YEAR_IN_SEC, { from: acc1 })

            // Wait 0.5 year
            await moneyMarketModule.timePass(0.5)

            // acc0 withdraws
            const acc0BeforeBalance = await stablecoin.balanceOf(acc0)
            await dInterestPool.withdraw(1, Base.INF, false, { from: acc0 })

            // Verify withdrawn amount
            const acc0CurrentBalance = await stablecoin.balanceOf(acc0)
            const acc0WithdrawnAmountExpected = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, true).plus(depositAmount)
            const acc0WithdrawnAmountActual = BigNumber(acc0CurrentBalance).minus(acc0BeforeBalance)
            Base.assertEpsilonEq(acc0WithdrawnAmountActual, acc0WithdrawnAmountExpected, 'acc0 didn\'t withdraw correct amount of stablecoin')

            // Verify totalDeposit
            const totalDeposit0 = BigNumber(await dInterestPool.totalDeposit())
            Base.assertEpsilonEq(totalDeposit0, depositAmount, 'totalDeposit not updated after acc0 withdrawed')

            // Wait 0.5 year
            await moneyMarketModule.timePass(0.5)

            // acc1 withdraws
            const acc1BeforeBalance = await stablecoin.balanceOf(acc1)
            await dInterestPool.withdraw(2, Base.INF, false, { from: acc1 })

            // Verify withdrawn amount
            const acc1CurrentBalance = await stablecoin.balanceOf(acc1)
            const acc1WithdrawnAmountExpected = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, true).plus(depositAmount)
            const acc1WithdrawnAmountActual = BigNumber(acc1CurrentBalance).minus(acc1BeforeBalance)
            Base.assertEpsilonEq(acc1WithdrawnAmountActual, acc1WithdrawnAmountExpected, 'acc1 didn\'t withdraw correct amount of stablecoin')

            // Verify totalDeposit
            const totalDeposit1 = BigNumber(await dInterestPool.totalDeposit())
            Base.assertEpsilonEq(totalDeposit1, 0, 'totalDeposit not updated after acc1 withdrawed')
          })
        })

        context('edge cases', () => {

        })
      })

      describe('fund', () => {
        context('happy path', () => {
          it('fund 10% at the beginning', async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + Base.YEAR_IN_SEC), { from: acc0 })

            // acc1 funds deposit
            await stablecoin.approve(dInterestPool.address, Base.INF, { from: acc1 })
            await dInterestPool.fund(1, Base.INF, { from: acc1 })

            // wait 1 year
            await moneyMarketModule.timePass(1)

            // withdraw deposit
            await dInterestPool.withdraw(1, Base.INF, false, { from: acc0 })

            // verify earned interest
            const acc1BeforeBalance = BigNumber(await stablecoin.balanceOf(acc1))
            await fundingMultitoken.withdrawDividend(1, stablecoin.address, { from: acc1 })
            const actualInterestAmount = BigNumber(await stablecoin.balanceOf(acc1)).minus(acc1BeforeBalance)
            const expectedInterestAmount = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, false).plus(depositAmount).times(INIT_INTEREST_RATE)
            Base.assertEpsilonEq(actualInterestAmount, expectedInterestAmount, 'funding interest earned incorrect')
          })

          it('two funders fund 70% at 20% maturation', async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + Base.YEAR_IN_SEC), { from: acc0 })

            // wait 0.2 year
            await moneyMarketModule.timePass(0.2)

            // acc1 funds 50%
            await stablecoin.approve(dInterestPool.address, Base.INF, { from: acc1 })
            const deficitAmount = BigNumber((await dInterestPool.surplusOfDeposit.call(1)).surplusAmount)
            await dInterestPool.fund(1, Base.num2str(deficitAmount.times(0.5)), { from: acc1 })

            // acc1 funds 20%
            await stablecoin.approve(dInterestPool.address, Base.INF, { from: acc2 })
            await dInterestPool.fund(1, Base.num2str(deficitAmount.times(0.2)), { from: acc2 })

            // wait 0.8 year
            await moneyMarketModule.timePass(0.8)

            // withdraw deposit
            await dInterestPool.withdraw(1, Base.INF, false, { from: acc0 })

            // verify earned interest
            const acc1BeforeBalance = BigNumber(await stablecoin.balanceOf(acc1))
            await fundingMultitoken.withdrawDividend(1, stablecoin.address, { from: acc1 })
            const actualAcc1InterestAmount = BigNumber(await stablecoin.balanceOf(acc1)).minus(acc1BeforeBalance)
            const expectedAcc1InterestAmount = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, false).plus(depositAmount).times(INIT_INTEREST_RATE).times(0.8).times(0.5)
            Base.assertEpsilonEq(actualAcc1InterestAmount, expectedAcc1InterestAmount, 'acc1 funding interest earned incorrect')

            const acc2BeforeBalance = BigNumber(await stablecoin.balanceOf(acc2))
            await fundingMultitoken.withdrawDividend(1, stablecoin.address, { from: acc2 })
            const actualAcc2InterestAmount = BigNumber(await stablecoin.balanceOf(acc2)).minus(acc2BeforeBalance)
            const expectedAcc2InterestAmount = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, false).plus(depositAmount).times(INIT_INTEREST_RATE).times(0.8).times(0.2)
            Base.assertEpsilonEq(actualAcc2InterestAmount, expectedAcc2InterestAmount, 'acc2 funding interest earned incorrect')
          })

          it('fund 10% then withdraw 50%', async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + Base.YEAR_IN_SEC), { from: acc0 })

            // acc1 funds 10%
            await stablecoin.approve(dInterestPool.address, Base.INF, { from: acc1 })
            const deficitAmount = BigNumber((await dInterestPool.surplusOfDeposit.call(1)).surplusAmount)
            await dInterestPool.fund(1, Base.num2str(deficitAmount.times(0.1)), { from: acc1 })

            // withdraw 50%
            const depositVirtualTokenTotalSupply = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, true).plus(depositAmount)
            await dInterestPool.withdraw(1, Base.num2str(depositVirtualTokenTotalSupply.times(0.5)), true, { from: acc0 })

            // wait 1 year
            await moneyMarketModule.timePass(1)

            // withdraw deposit
            await dInterestPool.withdraw(1, Base.INF, false, { from: acc0 })

            // verify earned interest
            const acc1BeforeBalance = BigNumber(await stablecoin.balanceOf(acc1))
            await fundingMultitoken.withdrawDividend(1, stablecoin.address, { from: acc1 })
            const actualInterestAmount = BigNumber(await stablecoin.balanceOf(acc1)).minus(acc1BeforeBalance)
            const expectedInterestAmount = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, false).plus(depositAmount).times(INIT_INTEREST_RATE).times(0.1)
            Base.assertEpsilonEq(actualInterestAmount, expectedInterestAmount, 'funding interest earned incorrect')
          })

          it('fund 90% then withdraw 50%', async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), Base.num2str(blockNow + Base.YEAR_IN_SEC), { from: acc0 })

            // acc1 funds 90%
            await stablecoin.approve(dInterestPool.address, Base.INF, { from: acc1 })
            const deficitAmount = BigNumber((await dInterestPool.surplusOfDeposit.call(1)).surplusAmount)
            await dInterestPool.fund(1, Base.num2str(deficitAmount.times(0.9)), { from: acc1 })

            // withdraw 50%
            const depositVirtualTokenTotalSupply = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, true).plus(depositAmount)
            await dInterestPool.withdraw(1, Base.num2str(depositVirtualTokenTotalSupply.times(0.5)), true, { from: acc0 })

            // verify refund
            {
              const acc1BeforeBalance = BigNumber(await stablecoin.balanceOf(acc1))
              await fundingMultitoken.withdrawDividend(1, stablecoin.address, { from: acc1 })
              const actualRefundAmount = BigNumber(await stablecoin.balanceOf(acc1)).minus(acc1BeforeBalance)
              const estimatedLostInterest = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, false).plus(depositAmount).times(INIT_INTEREST_RATE).times(0.9 + 0.5 - 1)
              const maxRefundAmount = deficitAmount.times(0.4)
              const expectedRefundAmount = BigNumber.min(estimatedLostInterest, maxRefundAmount)
              Base.assertEpsilonEq(actualRefundAmount, expectedRefundAmount, 'funding refund incorrect')
            }

            // wait 1 year
            await moneyMarketModule.timePass(1)

            // withdraw deposit
            await dInterestPool.withdraw(1, Base.INF, false, { from: acc0 })

            // verify earned interest
            const acc1BeforeBalance = BigNumber(await stablecoin.balanceOf(acc1))
            await fundingMultitoken.withdrawDividend(1, stablecoin.address, { from: acc1 })
            const actualInterestAmount = BigNumber(await stablecoin.balanceOf(acc1)).minus(acc1BeforeBalance)
            const expectedInterestAmount = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, false).plus(depositAmount).times(INIT_INTEREST_RATE).times(0.5)
            Base.assertEpsilonEq(actualInterestAmount, expectedInterestAmount, 'funding interest earned incorrect')
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
          it('single deposit, two payouts', async () => {
            const depositAmount = 10 * Base.STABLECOIN_PRECISION

            // acc0 deposits stablecoin into the DInterest pool for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), blockNow + Base.YEAR_IN_SEC, { from: acc0 })

            // Fund deficit using acc2
            await stablecoin.approve(dInterestPool.address, Base.INF, { from: acc2 })
            await dInterestPool.fund(1, Base.INF, { from: acc2 })

            // Wait 0.3 year
            await moneyMarketModule.timePass(0.3)

            // Payout interest
            await dInterestPool.payInterestToFunders(1, { from: acc2 })

            // Wait 0.7 year
            await moneyMarketModule.timePass(0.7)

            // Payout interest
            await dInterestPool.payInterestToFunders(1, { from: acc2 })

            // Withdraw deposit
            await dInterestPool.withdraw(1, Base.INF, false, { from: acc0 })

            // Redeem interest
            const beforeBalance = BigNumber(await stablecoin.balanceOf(acc2))
            await fundingMultitoken.withdrawDividend(1, stablecoin.address, { from: acc2 })

            // Check interest received
            const actualInterestReceived = BigNumber(await stablecoin.balanceOf(acc2)).minus(beforeBalance)
            const interestExpected = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, false).plus(depositAmount).times(INIT_INTEREST_RATE)
            Base.assertEpsilonEq(actualInterestReceived, interestExpected, 'interest received incorrect')
          })
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
          it('single deposit', async () => {
            const depositAmount = 10 * Base.STABLECOIN_PRECISION

            // acc0 deposits for 1 year
            await stablecoin.approve(dInterestPool.address, Base.num2str(depositAmount), { from: acc0 })
            const blockNow = await Base.latestBlockTimestamp()
            await dInterestPool.deposit(Base.num2str(depositAmount), blockNow + Base.YEAR_IN_SEC, { from: acc0 })

            // Fund deficit using acc2
            await stablecoin.approve(dInterestPool.address, Base.INF, { from: acc2 })
            await dInterestPool.fund(1, Base.INF, { from: acc2 })

            // Wait 1 year
            await moneyMarketModule.timePass(1)

            // Surplus should be zero, because the interest owed to funders should be deducted from surplus
            const surplusObj = await dInterestPool.surplus.call()
            Base.assertEpsilonEq(0, surplusObj.surplusAmount, 'surplus not 0')

            // totalInterestOwedToFunders() should return the interest generated by the deposit
            const totalInterestOwedToFunders = await dInterestPool.totalInterestOwedToFunders.call()
            const interestExpected = Base.calcInterestAmount(depositAmount, INIT_INTEREST_RATE_PER_SECOND, Base.YEAR_IN_SEC, false).plus(depositAmount).times(INIT_INTEREST_RATE)
            Base.assertEpsilonEq(totalInterestOwedToFunders, interestExpected, 'interest owed to funders not correct')
          })
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
