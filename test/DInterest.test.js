const Base = require("./base");
const BigNumber = require("bignumber.js");
const { assert } = require("hardhat");

contract("DInterest", accounts => {
  // Accounts
  const acc0 = accounts[0];
  const acc1 = accounts[1];
  const acc2 = accounts[2];
  const govTreasury = accounts[3];
  const devWallet = accounts[4];

  // Contract instances
  let baseContracts;

  // Constants
  const INIT_INTEREST_RATE = 0.1; // 10% APY
  const INIT_INTEREST_RATE_PER_SECOND = 0.1 / Base.YEAR_IN_SEC; // 10% APY

  for (const moduleInfo of Base.moneyMarketModuleList) {
    const moneyMarketModule = moduleInfo.moduleGenerator();
    context(`Money market: ${moduleInfo.name}`, () => {
      beforeEach(async () => {
        baseContracts = await Base.setupTest(accounts, moneyMarketModule);
      });

      describe("deposit", () => {
        context("happy path", () => {
          it("should update global variables correctly", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // Calculate interest amount
            const expectedInterest = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              true
            );

            // Verify totalDeposit
            const totalDeposit = BigNumber(
              await baseContracts.dInterestPool.totalDeposit()
            );
            Base.assertEpsilonEq(
              totalDeposit,
              depositAmount,
              "totalDeposit not updated after acc0 deposited"
            );

            // Verify totalInterestOwed
            const totalInterestOwed = BigNumber(
              await baseContracts.dInterestPool.totalInterestOwed()
            );
            Base.assertEpsilonEq(
              totalInterestOwed,
              expectedInterest,
              "totalInterestOwed not updated after acc0 deposited"
            );

            // Verify totalFeeOwed
            const totalFeeOwed = BigNumber(
              await baseContracts.dInterestPool.totalFeeOwed()
            );
            const expectedTotalFeeOwed = totalInterestOwed
              .plus(totalFeeOwed)
              .minus(Base.applyFee(totalInterestOwed.plus(totalFeeOwed)));
            Base.assertEpsilonEq(
              totalFeeOwed,
              expectedTotalFeeOwed,
              "totalFeeOwed not updated after acc0 deposited"
            );
          });

          it("should transfer funds correctly", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            const acc0BeforeBalance = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc0)
            );
            const dInterestPoolBeforeBalance = BigNumber(
              await baseContracts.market.totalValue.call()
            );
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            const acc0CurrentBalance = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc0)
            );
            const dInterestPoolCurrentBalance = BigNumber(
              await baseContracts.market.totalValue.call()
            );

            // Verify stablecoin transferred out of account
            Base.assertEpsilonEq(
              acc0BeforeBalance.minus(acc0CurrentBalance),
              depositAmount,
              "stablecoin not transferred out of acc0"
            );

            // Verify stablecoin transferred into money market
            Base.assertEpsilonEq(
              dInterestPoolCurrentBalance.minus(dInterestPoolBeforeBalance),
              depositAmount,
              "stablecoin not transferred into money market"
            );
          });
        });

        context("edge cases", () => {
          it("should fail with very short deposit period", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 second
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            try {
              await baseContracts.dInterestPool.deposit(
                Base.num2str(depositAmount),
                Base.num2str(blockNow + 1),
                { from: acc0 }
              );
              assert.fail();
            } catch (error) {}
          });

          it("should fail with greater than maximum deposit period", async function() {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 10 years
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            try {
              await baseContracts.dInterestPool.deposit(
                Base.num2str(depositAmount),
                Base.num2str(blockNow + 10 * Base.YEAR_IN_SEC),
                { from: acc0 }
              );
              assert.fail();
            } catch (error) {}
          });

          it("should fail with less than minimum deposit amount", async function() {
            const depositAmount = 0.001 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            try {
              await baseContracts.dInterestPool.deposit(
                Base.num2str(depositAmount),
                Base.num2str(blockNow + Base.YEAR_IN_SEC),
                { from: acc0 }
              );
              assert.fail();
            } catch (error) {}
          });
        });
      });

      describe("topupDeposit", () => {
        context("happy path", () => {
          it("should update global variables correctly", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // topup
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            await baseContracts.dInterestPool.topupDeposit(
              1,
              Base.num2str(depositAmount),
              {
                from: acc0
              }
            );

            // Calculate interest amount
            const expectedInterest = Base.calcInterestAmount(
              2 * depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              true
            );

            // Verify totalDeposit
            const totalDeposit = BigNumber(
              await baseContracts.dInterestPool.totalDeposit()
            );
            Base.assertEpsilonEq(
              totalDeposit,
              2 * depositAmount,
              "totalDeposit not updated after acc0 deposited"
            );

            // Verify totalInterestOwed
            const totalInterestOwed = BigNumber(
              await baseContracts.dInterestPool.totalInterestOwed()
            );
            Base.assertEpsilonEq(
              totalInterestOwed,
              expectedInterest,
              "totalInterestOwed not updated after acc0 deposited"
            );

            // Verify totalFeeOwed
            const totalFeeOwed = BigNumber(
              await baseContracts.dInterestPool.totalFeeOwed()
            );
            const expectedTotalFeeOwed = totalInterestOwed
              .plus(totalFeeOwed)
              .minus(Base.applyFee(totalInterestOwed.plus(totalFeeOwed)));
            Base.assertEpsilonEq(
              totalFeeOwed,
              expectedTotalFeeOwed,
              "totalFeeOwed not updated after acc0 deposited"
            );
          });

          it("should transfer funds correctly", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // topup
            const acc0BeforeBalance = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc0)
            );
            const dInterestPoolBeforeBalance = BigNumber(
              await baseContracts.market.totalValue.call()
            );
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            await baseContracts.dInterestPool.topupDeposit(
              1,
              Base.num2str(depositAmount),
              {
                from: acc0
              }
            );

            const acc0CurrentBalance = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc0)
            );
            const dInterestPoolCurrentBalance = BigNumber(
              await baseContracts.market.totalValue.call()
            );

            // Verify stablecoin transferred out of account
            Base.assertEpsilonEq(
              acc0BeforeBalance.minus(acc0CurrentBalance),
              depositAmount,
              "stablecoin not transferred out of acc0"
            );

            // Verify stablecoin transferred into money market
            Base.assertEpsilonEq(
              dInterestPoolCurrentBalance.minus(dInterestPoolBeforeBalance),
              depositAmount,
              "stablecoin not transferred into money market"
            );
          });

          it("should withdraw correctly", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // topup
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            await baseContracts.dInterestPool.topupDeposit(
              1,
              Base.num2str(depositAmount),
              {
                from: acc0
              }
            );

            // wait 1 year
            await moneyMarketModule.timePass(1);

            // withdraw
            const acc0BeforeBalance = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc0)
            );
            const dInterestPoolBeforeBalance = BigNumber(
              await baseContracts.market.totalValue.call()
            );
            await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
              from: acc0
            });
            const acc0CurrentBalance = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc0)
            );
            const dInterestPoolCurrentBalance = BigNumber(
              await baseContracts.market.totalValue.call()
            );

            // Verify totalDeposit
            const totalDeposit = BigNumber(
              await baseContracts.dInterestPool.totalDeposit()
            );
            Base.assertEpsilonEq(
              totalDeposit,
              0,
              "totalDeposit not updated after acc0 withdrew"
            );

            // Verify totalInterestOwed
            const totalInterestOwed = BigNumber(
              await baseContracts.dInterestPool.totalInterestOwed()
            );
            Base.assertEpsilonEq(
              totalInterestOwed,
              0,
              "totalInterestOwed not updated after acc0 withdrew"
            );

            // Verify totalFeeOwed
            const totalFeeOwed = BigNumber(
              await baseContracts.dInterestPool.totalFeeOwed()
            );
            Base.assertEpsilonEq(
              totalFeeOwed,
              0,
              "totalFeeOwed not updated after acc0 withdrew"
            );

            // Verify stablecoin transferred to account
            const expectedInterest = Base.calcInterestAmount(
              2 * depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              true
            );
            const expectedWithdrawAmount = expectedInterest.plus(
              2 * depositAmount
            );
            Base.assertEpsilonEq(
              acc0CurrentBalance.minus(acc0BeforeBalance),
              expectedWithdrawAmount,
              "stablecoin not transferred to acc0"
            );

            // Verify stablecoin transferred from money market
            const expectedInterestPlusFee = Base.calcInterestAmount(
              2 * depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            );
            const expectedPoolValueChange = expectedInterestPlusFee.plus(
              2 * depositAmount
            );
            Base.assertEpsilonEq(
              dInterestPoolBeforeBalance.minus(dInterestPoolCurrentBalance),
              expectedPoolValueChange,
              "stablecoin not transferred from money market"
            );
          });
        });

        context("edge cases", () => {});
      });

      describe("rolloverDeposit", () => {
        context("happy path", () => {
          const depositAmount = 100 * Base.STABLECOIN_PRECISION;

          beforeEach(async () => {
            // acc0 deposits
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );
          });

          it("should create a new deposit with new maturationTimestamp and deposit amount increased", async function() {
            // Wait 1 year (maturation time)
            await moneyMarketModule.timePass(1);
            const blockNow = await Base.latestBlockTimestamp();

            // calculate first deposit withdrawn value
            const valueOfFirstDepositAfterMaturation = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              true
            ).plus(depositAmount);
            const valueOfRolloverDepositAfterMaturation = Base.calcInterestAmount(
              valueOfFirstDepositAfterMaturation,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              true
            ).plus(valueOfFirstDepositAfterMaturation);
            await baseContracts.dInterestPool.rolloverDeposit(
              Base.num2str(1),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            const deposit1 = await baseContracts.dInterestPool.getDeposit(
              Base.num2str(1)
            );
            const deposit2 = await baseContracts.dInterestPool.getDeposit(
              Base.num2str(2)
            );
            assert.equal(
              deposit1.virtualTokenTotalSupply,
              0,
              "old deposit value must be equals 0"
            );
            assert.equal(
              deposit2.maturationTimestamp,
              blockNow + Base.YEAR_IN_SEC,
              "new deposit maturation time is not correct"
            );
            Base.assertEpsilonEq(
              deposit2.virtualTokenTotalSupply,
              valueOfRolloverDepositAfterMaturation,
              "rollover deposit do not have the correct token number"
            );
          });
        });

        context("edge cases", () => {});
      });

      describe("withdraw", () => {
        context("withdraw after maturation", () => {
          const depositAmount = 100 * Base.STABLECOIN_PRECISION;

          beforeEach(async () => {
            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // Wait 1 year
            await moneyMarketModule.timePass(1);
          });

          context("full withdrawal", () => {
            it("should update global variables correctly", async () => {
              // Withdraw
              await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
                from: acc0
              });

              // Verify totalDeposit
              const totalDeposit = BigNumber(
                await baseContracts.dInterestPool.totalDeposit()
              );
              Base.assertEpsilonEq(totalDeposit, 0, "totalDeposit incorrect");

              // Verify totalInterestOwed
              const totalInterestOwed = BigNumber(
                await baseContracts.dInterestPool.totalInterestOwed()
              );
              Base.assertEpsilonEq(
                totalInterestOwed,
                0,
                "totalInterestOwed incorrect"
              );

              // Verify totalFeeOwed
              const totalFeeOwed = BigNumber(
                await baseContracts.dInterestPool.totalFeeOwed()
              );
              Base.assertEpsilonEq(totalFeeOwed, 0, "totalFeeOwed incorrect");
            });

            it("should transfer funds correctly", async function() {
              const acc0BeforeBalance = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc0)
              );
              const dInterestPoolBeforeBalance = BigNumber(
                await baseContracts.market.totalValue.call()
              );

              // Withdraw
              await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
                from: acc0
              });

              const acc0CurrentBalance = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc0)
              );
              const dInterestPoolCurrentBalance = BigNumber(
                await baseContracts.market.totalValue.call()
              );

              // Verify stablecoin transferred into account
              const expectedInterest = Base.calcInterestAmount(
                depositAmount,
                INIT_INTEREST_RATE_PER_SECOND,
                Base.YEAR_IN_SEC,
                true
              );
              const expectedWithdrawAmount = expectedInterest.plus(
                depositAmount
              );
              Base.assertEpsilonEq(
                acc0CurrentBalance.minus(acc0BeforeBalance),
                expectedWithdrawAmount,
                "stablecoin not transferred into acc0"
              );

              // Verify stablecoin transferred into money market
              const actualPoolValueChange = dInterestPoolBeforeBalance.minus(
                dInterestPoolCurrentBalance
              );
              const expectedPoolValueChange = Base.calcInterestAmount(
                depositAmount,
                INIT_INTEREST_RATE_PER_SECOND,
                Base.YEAR_IN_SEC,
                false
              ).plus(depositAmount);
              Base.assertEpsilonEq(
                actualPoolValueChange,
                expectedPoolValueChange,
                "stablecoin not transferred out of money market"
              );
            });
          });

          context("partial withdrawal", async () => {
            const withdrawProportion = 0.7;
            let virtualTokenTotalSupply, withdrawVirtualTokenAmount;

            beforeEach(async () => {
              virtualTokenTotalSupply = BigNumber(
                (await baseContracts.dInterestPool.getDeposit(1))
                  .virtualTokenTotalSupply
              );
              withdrawVirtualTokenAmount = virtualTokenTotalSupply
                .times(withdrawProportion)
                .integerValue();
            });

            it("should update global variables correctly", async () => {
              // Withdraw
              await baseContracts.dInterestPool.withdraw(
                1,
                Base.num2str(withdrawVirtualTokenAmount),
                false,
                { from: acc0 }
              );

              // Verify totalDeposit
              const totalDeposit = BigNumber(
                await baseContracts.dInterestPool.totalDeposit()
              );
              Base.assertEpsilonEq(
                totalDeposit,
                depositAmount * (1 - withdrawProportion),
                "totalDeposit incorrect"
              );

              // Verify totalInterestOwed
              const totalInterestOwed = BigNumber(
                await baseContracts.dInterestPool.totalInterestOwed()
              );
              const expectedInterest = Base.calcInterestAmount(
                depositAmount,
                INIT_INTEREST_RATE_PER_SECOND,
                Base.YEAR_IN_SEC,
                true
              ).times(1 - withdrawProportion);
              Base.assertEpsilonEq(
                totalInterestOwed,
                expectedInterest,
                "totalInterestOwed incorrect"
              );

              // Verify totalFeeOwed
              const totalFeeOwed = BigNumber(
                await baseContracts.dInterestPool.totalFeeOwed()
              );
              const expectedTotalFeeOwed = Base.calcFeeAmount(
                Base.calcInterestAmount(
                  depositAmount,
                  INIT_INTEREST_RATE_PER_SECOND,
                  Base.YEAR_IN_SEC,
                  false
                )
              ).times(1 - withdrawProportion);
              Base.assertEpsilonEq(
                totalFeeOwed,
                expectedTotalFeeOwed,
                "totalFeeOwed incorrect"
              );
            });

            it("should transfer funds correctly", async function() {
              const acc0BeforeBalance = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc0)
              );
              const dInterestPoolBeforeBalance = BigNumber(
                await baseContracts.market.totalValue.call()
              );

              // Withdraw
              await baseContracts.dInterestPool.withdraw(
                1,
                Base.num2str(withdrawVirtualTokenAmount),
                false,
                { from: acc0 }
              );

              const acc0CurrentBalance = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc0)
              );
              const dInterestPoolCurrentBalance = BigNumber(
                await baseContracts.market.totalValue.call()
              );

              // Verify stablecoin transferred into account
              const expectedInterest = Base.calcInterestAmount(
                depositAmount,
                INIT_INTEREST_RATE_PER_SECOND,
                Base.YEAR_IN_SEC,
                true
              );
              const expectedWithdrawAmount = expectedInterest
                .plus(depositAmount)
                .times(withdrawProportion);
              Base.assertEpsilonEq(
                acc0CurrentBalance.minus(acc0BeforeBalance),
                expectedWithdrawAmount,
                "stablecoin not transferred into acc0"
              );

              // Verify stablecoin transferred into money market
              const actualPoolValueChange = dInterestPoolBeforeBalance.minus(
                dInterestPoolCurrentBalance
              );
              const expectedPoolValueChange = Base.calcInterestAmount(
                depositAmount,
                INIT_INTEREST_RATE_PER_SECOND,
                Base.YEAR_IN_SEC,
                false
              )
                .plus(depositAmount)
                .times(withdrawProportion);
              Base.assertEpsilonEq(
                actualPoolValueChange,
                expectedPoolValueChange,
                "stablecoin not transferred out of money market"
              );
            });
          });
        });

        context("withdraw before maturation", () => {
          const depositAmount = 100 * Base.STABLECOIN_PRECISION;

          beforeEach(async () => {
            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // Wait 0.5 year
            await moneyMarketModule.timePass(0.5);
          });

          context("full withdrawal", () => {
            it("should update global variables correctly", async () => {
              // Withdraw
              await baseContracts.dInterestPool.withdraw(1, Base.INF, true, {
                from: acc0
              });

              // Verify totalDeposit
              const totalDeposit = BigNumber(
                await baseContracts.dInterestPool.totalDeposit()
              );
              Base.assertEpsilonEq(totalDeposit, 0, "totalDeposit incorrect");

              // Verify totalInterestOwed
              const totalInterestOwed = BigNumber(
                await baseContracts.dInterestPool.totalInterestOwed()
              );
              Base.assertEpsilonEq(
                totalInterestOwed,
                0,
                "totalInterestOwed incorrect"
              );

              // Verify totalFeeOwed
              const totalFeeOwed = BigNumber(
                await baseContracts.dInterestPool.totalFeeOwed()
              );
              Base.assertEpsilonEq(totalFeeOwed, 0, "totalFeeOwed incorrect");
            });

            it("should transfer funds correctly", async () => {
              const acc0BeforeBalance = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc0)
              );
              const dInterestPoolBeforeBalance = BigNumber(
                await baseContracts.market.totalValue.call()
              );

              // Withdraw
              await baseContracts.dInterestPool.withdraw(1, Base.INF, true, {
                from: acc0
              });

              const acc0CurrentBalance = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc0)
              );
              const dInterestPoolCurrentBalance = BigNumber(
                await baseContracts.market.totalValue.call()
              );

              // Verify stablecoin transferred into account
              const expectedReceiveStablecoinAmount = Base.applyEarlyWithdrawFee(
                depositAmount
              );
              Base.assertEpsilonEq(
                acc0CurrentBalance.minus(acc0BeforeBalance),
                expectedReceiveStablecoinAmount,
                "stablecoin not transferred into acc0"
              );

              // Verify stablecoin transferred from money market
              const actualPoolValueChange = dInterestPoolBeforeBalance.minus(
                dInterestPoolCurrentBalance
              );
              Base.assertEpsilonEq(
                actualPoolValueChange,
                depositAmount,
                "stablecoin not transferred out of money market"
              );
            });
          });

          context("partial withdrawal", async () => {
            const withdrawProportion = 0.7;
            let virtualTokenTotalSupply, withdrawVirtualTokenAmount;

            beforeEach(async () => {
              virtualTokenTotalSupply = BigNumber(
                (await baseContracts.dInterestPool.getDeposit(1))
                  .virtualTokenTotalSupply
              );
              withdrawVirtualTokenAmount = virtualTokenTotalSupply
                .times(withdrawProportion)
                .integerValue();
            });

            it("should update global variables correctly", async () => {
              // Withdraw
              await baseContracts.dInterestPool.withdraw(
                1,
                Base.num2str(withdrawVirtualTokenAmount),
                true,
                { from: acc0 }
              );

              // Verify totalDeposit
              const totalDeposit = BigNumber(
                await baseContracts.dInterestPool.totalDeposit()
              );
              Base.assertEpsilonEq(
                totalDeposit,
                depositAmount * (1 - withdrawProportion),
                "totalDeposit incorrect"
              );

              // Verify totalInterestOwed
              const totalInterestOwed = BigNumber(
                await baseContracts.dInterestPool.totalInterestOwed()
              );
              const expectedInterest = Base.calcInterestAmount(
                depositAmount,
                INIT_INTEREST_RATE_PER_SECOND,
                Base.YEAR_IN_SEC,
                true
              ).times(1 - withdrawProportion);
              Base.assertEpsilonEq(
                totalInterestOwed,
                expectedInterest,
                "totalInterestOwed incorrect"
              );

              // Verify totalFeeOwed
              const totalFeeOwed = BigNumber(
                await baseContracts.dInterestPool.totalFeeOwed()
              );
              const expectedTotalFeeOwed = Base.calcFeeAmount(
                Base.calcInterestAmount(
                  depositAmount,
                  INIT_INTEREST_RATE_PER_SECOND,
                  Base.YEAR_IN_SEC,
                  false
                )
              ).times(1 - withdrawProportion);
              Base.assertEpsilonEq(
                totalFeeOwed,
                expectedTotalFeeOwed,
                "totalFeeOwed incorrect"
              );
            });

            it("should transfer funds correctly", async function() {
              const acc0BeforeBalance = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc0)
              );
              const dInterestPoolBeforeBalance = BigNumber(
                await baseContracts.market.totalValue.call()
              );

              // Withdraw
              await baseContracts.dInterestPool.withdraw(
                1,
                Base.num2str(withdrawVirtualTokenAmount),
                true,
                { from: acc0 }
              );

              const acc0CurrentBalance = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc0)
              );
              const dInterestPoolCurrentBalance = BigNumber(
                await baseContracts.market.totalValue.call()
              );

              // Verify stablecoin transferred into account
              const expectedWithdrawAmount = Base.applyEarlyWithdrawFee(
                BigNumber(depositAmount).times(withdrawProportion)
              );
              Base.assertEpsilonEq(
                acc0CurrentBalance.minus(acc0BeforeBalance),
                expectedWithdrawAmount,
                "stablecoin not transferred into acc0"
              );

              // Verify stablecoin transferred into money market
              const actualPoolValueChange = dInterestPoolBeforeBalance.minus(
                dInterestPoolCurrentBalance
              );
              const expectedPoolValueChange = BigNumber(depositAmount).times(
                withdrawProportion
              );
              Base.assertEpsilonEq(
                actualPoolValueChange,
                expectedPoolValueChange,
                "stablecoin not transferred out of money market"
              );
            });
          });
        });

        context("complex examples", () => {
          it("two deposits with overlap", async () => {
            const depositAmount = 10 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            let blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              blockNow + Base.YEAR_IN_SEC,
              { from: acc0 }
            );

            // Wait 0.5 year
            await moneyMarketModule.timePass(0.5);

            // acc1 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc1 }
            );
            blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              blockNow + Base.YEAR_IN_SEC,
              { from: acc1 }
            );

            // Wait 0.5 year
            await moneyMarketModule.timePass(0.5);

            // acc0 withdraws
            const acc0BeforeBalance = await baseContracts.stablecoin.balanceOf(
              acc0
            );
            await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
              from: acc0
            });

            // Verify withdrawn amount
            const acc0CurrentBalance = await baseContracts.stablecoin.balanceOf(
              acc0
            );
            const acc0WithdrawnAmountExpected = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              true
            ).plus(depositAmount);
            const acc0WithdrawnAmountActual = BigNumber(
              acc0CurrentBalance
            ).minus(acc0BeforeBalance);
            Base.assertEpsilonEq(
              acc0WithdrawnAmountActual,
              acc0WithdrawnAmountExpected,
              "acc0 didn't withdraw correct amount of stablecoin"
            );

            // Verify totalDeposit
            const totalDeposit0 = BigNumber(
              await baseContracts.dInterestPool.totalDeposit()
            );
            Base.assertEpsilonEq(
              totalDeposit0,
              depositAmount,
              "totalDeposit not updated after acc0 withdrawed"
            );

            // Wait 0.5 year
            await moneyMarketModule.timePass(0.5);

            // acc1 withdraws
            const acc1BeforeBalance = await baseContracts.stablecoin.balanceOf(
              acc1
            );
            await baseContracts.dInterestPool.withdraw(2, Base.INF, false, {
              from: acc1
            });

            // Verify withdrawn amount
            const acc1CurrentBalance = await baseContracts.stablecoin.balanceOf(
              acc1
            );
            const acc1WithdrawnAmountExpected = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              true
            ).plus(depositAmount);
            const acc1WithdrawnAmountActual = BigNumber(
              acc1CurrentBalance
            ).minus(acc1BeforeBalance);
            Base.assertEpsilonEq(
              acc1WithdrawnAmountActual,
              acc1WithdrawnAmountExpected,
              "acc1 didn't withdraw correct amount of stablecoin"
            );

            // Verify totalDeposit
            const totalDeposit1 = BigNumber(
              await baseContracts.dInterestPool.totalDeposit()
            );
            Base.assertEpsilonEq(
              totalDeposit1,
              0,
              "totalDeposit not updated after acc1 withdrawed"
            );
          });
        });

        context("edge cases", () => {});
      });

      describe("fund", () => {
        context("happy path", () => {
          it("fund 10% at the beginning", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // acc1 funds deposit
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.INF,
              {
                from: acc1
              }
            );
            await baseContracts.dInterestPool.fund(1, Base.INF, { from: acc1 });

            // wait 1 year
            await moneyMarketModule.timePass(1);

            // withdraw deposit
            await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
              from: acc0
            });

            // verify earned interest
            const acc1BeforeBalance = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc1)
            );
            await baseContracts.fundingMultitoken.withdrawDividend(
              1,
              baseContracts.stablecoin.address,
              {
                from: acc1
              }
            );
            const actualInterestAmount = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc1)
            ).minus(acc1BeforeBalance);
            const totalPrincipal = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            ).plus(depositAmount);
            const expectedInterestAmount = totalPrincipal.times(
              INIT_INTEREST_RATE
            );
            Base.assertEpsilonEq(
              actualInterestAmount,
              expectedInterestAmount,
              "funding interest earned incorrect"
            );
          });

          it("two funders fund 70% at 20% maturation", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // wait 0.2 year
            await moneyMarketModule.timePass(0.2);

            // acc1 funds 50%
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.INF,
              {
                from: acc1
              }
            );
            const deficitAmount = BigNumber(
              (await baseContracts.dInterestPool.surplusOfDeposit.call(1))
                .surplusAmount
            );
            await baseContracts.dInterestPool.fund(
              1,
              Base.num2str(deficitAmount.times(0.5)),
              { from: acc1 }
            );

            // acc1 funds 20%
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.INF,
              {
                from: acc2
              }
            );
            await baseContracts.dInterestPool.fund(
              1,
              Base.num2str(deficitAmount.times(0.2)),
              { from: acc2 }
            );

            // wait 0.8 year
            await moneyMarketModule.timePass(0.8);

            // withdraw deposit
            await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
              from: acc0
            });

            // verify earned interest
            const totalPrincipal = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            ).plus(depositAmount);

            const acc1BeforeBalance = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc1)
            );
            await baseContracts.fundingMultitoken.withdrawDividend(
              1,
              baseContracts.stablecoin.address,
              {
                from: acc1
              }
            );
            const actualAcc1InterestAmount = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc1)
            ).minus(acc1BeforeBalance);
            const expectedAcc1InterestAmount = totalPrincipal
              .times(INIT_INTEREST_RATE)
              .times(0.8)
              .times(0.5);
            Base.assertEpsilonEq(
              actualAcc1InterestAmount,
              expectedAcc1InterestAmount,
              "acc1 funding interest earned incorrect"
            );

            const acc2BeforeBalance = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc2)
            );
            await baseContracts.fundingMultitoken.withdrawDividend(
              1,
              baseContracts.stablecoin.address,
              {
                from: acc2
              }
            );
            const actualAcc2InterestAmount = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc2)
            ).minus(acc2BeforeBalance);
            const expectedAcc2InterestAmount = totalPrincipal
              .times(INIT_INTEREST_RATE)
              .times(0.8)
              .times(0.2);
            Base.assertEpsilonEq(
              actualAcc2InterestAmount,
              expectedAcc2InterestAmount,
              "acc2 funding interest earned incorrect"
            );
          });

          it("fund 10% then withdraw 50%", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // acc1 funds 10%
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.INF,
              {
                from: acc1
              }
            );
            const deficitAmount = BigNumber(
              (await baseContracts.dInterestPool.surplusOfDeposit.call(1))
                .surplusAmount
            );
            await baseContracts.dInterestPool.fund(
              1,
              Base.num2str(deficitAmount.times(0.1)),
              { from: acc1 }
            );

            // withdraw 50%
            const depositVirtualTokenTotalSupply = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              true
            ).plus(depositAmount);
            await baseContracts.dInterestPool.withdraw(
              1,
              Base.num2str(depositVirtualTokenTotalSupply.times(0.5)),
              true,
              { from: acc0 }
            );

            // wait 1 year
            await moneyMarketModule.timePass(1);

            // withdraw deposit
            await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
              from: acc0
            });

            // verify earned interest
            const acc1BeforeBalance = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc1)
            );
            await baseContracts.fundingMultitoken.withdrawDividend(
              1,
              baseContracts.stablecoin.address,
              {
                from: acc1
              }
            );
            const actualInterestAmount = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc1)
            ).minus(acc1BeforeBalance);
            const totalPrincipal = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            ).plus(depositAmount);
            const expectedInterestAmount = totalPrincipal
              .times(INIT_INTEREST_RATE)
              .times(0.1);
            Base.assertEpsilonEq(
              actualInterestAmount,
              expectedInterestAmount,
              "funding interest earned incorrect"
            );
          });

          it("fund 90% then withdraw 50%", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // acc1 funds 90%
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.INF,
              {
                from: acc1
              }
            );
            const deficitAmount = BigNumber(
              (await baseContracts.dInterestPool.surplusOfDeposit.call(1))
                .surplusAmount
            );
            await baseContracts.dInterestPool.fund(
              1,
              Base.num2str(deficitAmount.times(0.9)),
              { from: acc1 }
            );

            // withdraw 50%
            const depositVirtualTokenTotalSupply = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              true
            ).plus(depositAmount);
            await baseContracts.dInterestPool.withdraw(
              1,
              Base.num2str(depositVirtualTokenTotalSupply.times(0.5)),
              true,
              { from: acc0 }
            );

            // verify refund
            const totalPrincipal = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            ).plus(depositAmount);
            {
              const acc1BeforeBalance = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc1)
              );
              await baseContracts.fundingMultitoken.withdrawDividend(
                1,
                baseContracts.stablecoin.address,
                {
                  from: acc1
                }
              );
              const actualRefundAmount = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc1)
              ).minus(acc1BeforeBalance);
              const estimatedLostInterest = totalPrincipal
                .times(INIT_INTEREST_RATE)
                .times(0.9 + 0.5 - 1);
              const maxRefundAmount = deficitAmount.times(0.4);
              const expectedRefundAmount = BigNumber.min(
                estimatedLostInterest,
                maxRefundAmount
              );
              Base.assertEpsilonEq(
                actualRefundAmount,
                expectedRefundAmount,
                "funding refund incorrect"
              );
            }

            // wait 1 year
            await moneyMarketModule.timePass(1);

            // withdraw deposit
            await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
              from: acc0
            });

            // verify earned interest
            const acc1BeforeBalance = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc1)
            );
            await baseContracts.fundingMultitoken.withdrawDividend(
              1,
              baseContracts.stablecoin.address,
              {
                from: acc1
              }
            );
            const actualInterestAmount = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc1)
            ).minus(acc1BeforeBalance);
            const expectedInterestAmount = totalPrincipal
              .times(INIT_INTEREST_RATE)
              .times(0.5);
            Base.assertEpsilonEq(
              actualInterestAmount,
              expectedInterestAmount,
              "funding interest earned incorrect"
            );
          });
        });

        context("complex cases", () => {
          it("one funder funds 10% at the beginning, then another funder funds 70% at 20% maturation", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // acc1 funds 10%
            {
              await baseContracts.stablecoin.approve(
                baseContracts.dInterestPool.address,
                Base.INF,
                {
                  from: acc1
                }
              );
              const deficitAmount = BigNumber(
                (await baseContracts.dInterestPool.surplusOfDeposit.call(1))
                  .surplusAmount
              );
              await baseContracts.dInterestPool.fund(
                1,
                Base.num2str(deficitAmount.times(0.1)),
                { from: acc1 }
              );
            }

            // wait 0.2 year
            await moneyMarketModule.timePass(0.2);

            // acc2 funds 70%
            {
              await baseContracts.stablecoin.approve(
                baseContracts.dInterestPool.address,
                Base.INF,
                {
                  from: acc2
                }
              );
              const deficitAmount = BigNumber(
                (await baseContracts.dInterestPool.surplusOfDeposit.call(1))
                  .surplusAmount
              );
              await baseContracts.dInterestPool.fund(
                1,
                Base.num2str(deficitAmount.times(0.7).div(0.9)),
                { from: acc2 }
              );
            }

            // wait 0.8 year
            await moneyMarketModule.timePass(0.8);

            // withdraw deposit
            await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
              from: acc0
            });

            // verify earned interest for acc1
            const totalPrincipal = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            ).plus(depositAmount);
            {
              const acc1BeforeBalance = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc1)
              );
              await baseContracts.fundingMultitoken.withdrawDividend(
                1,
                baseContracts.stablecoin.address,
                {
                  from: acc1
                }
              );
              const actualInterestAmount = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc1)
              ).minus(acc1BeforeBalance);
              const expectedInterestAmount = totalPrincipal
                .times(INIT_INTEREST_RATE)
                .times(0.1);
              Base.assertEpsilonEq(
                actualInterestAmount,
                expectedInterestAmount,
                "acc1 funding interest earned incorrect"
              );
            }

            // verify earned interest for acc2
            {
              const acc2BeforeBalance = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc2)
              );
              await baseContracts.fundingMultitoken.withdrawDividend(
                1,
                baseContracts.stablecoin.address,
                {
                  from: acc2
                }
              );
              const actualInterestAmount = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc2)
              ).minus(acc2BeforeBalance);
              const expectedInterestAmount = totalPrincipal
                .times(INIT_INTEREST_RATE)
                .times(0.7)
                .times(0.8);
              Base.assertEpsilonEq(
                actualInterestAmount,
                expectedInterestAmount,
                "acc2 funding interest earned incorrect"
              );
            }
          });
        });

        context("edge cases", () => {
          it("fund 90%, wait, withdraw 100%, topup, fund 60%", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // acc1 funds 90%
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.INF,
              {
                from: acc1
              }
            );
            const deficitAmount = BigNumber(
              (await baseContracts.dInterestPool.surplusOfDeposit.call(1))
                .surplusAmount
            );
            await baseContracts.dInterestPool.fund(
              1,
              Base.num2str(deficitAmount.times(0.9)),
              { from: acc1 }
            );

            // wait 0.1 year
            await moneyMarketModule.timePass(0.1);

            // withdraw 100%
            const depositVirtualTokenTotalSupply = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              true
            ).plus(depositAmount);
            await baseContracts.dInterestPool.withdraw(
              1,
              Base.num2str(depositVirtualTokenTotalSupply.times(1)),
              true,
              { from: acc0 }
            );

            // verify received interest + refund
            const totalPrincipal = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            ).plus(depositAmount);
            {
              const acc1BeforeBalance = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc1)
              );
              await baseContracts.fundingMultitoken.withdrawDividend(
                1,
                baseContracts.stablecoin.address,
                {
                  from: acc1
                }
              );
              const actualReceivedAmount = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc1)
              ).minus(acc1BeforeBalance);
              const estimatedLostInterest = totalPrincipal
                .times(INIT_INTEREST_RATE)
                .times(0.9)
                .times(0.9);
              const maxRefundAmount = deficitAmount.times(0.9);
              const expectedRefundAmount = BigNumber.min(
                estimatedLostInterest,
                maxRefundAmount
              );
              const expectedInterestAmount = totalPrincipal
                .times(INIT_INTEREST_RATE)
                .times(0.9)
                .times(0.1);
              Base.assertEpsilonEq(
                actualReceivedAmount,
                expectedRefundAmount.plus(expectedInterestAmount),
                "funding refund incorrect"
              );
            }

            // topup
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            await baseContracts.dInterestPool.topupDeposit(
              1,
              Base.num2str(depositAmount),
              {
                from: acc0
              }
            );

            // acc1 funds 60%
            {
              await baseContracts.stablecoin.approve(
                baseContracts.dInterestPool.address,
                Base.INF,
                {
                  from: acc1
                }
              );
              const deficitAmount = BigNumber(
                (await baseContracts.dInterestPool.surplusOfDeposit.call(1))
                  .surplusAmount
              );
              await baseContracts.dInterestPool.fund(
                1,
                Base.num2str(deficitAmount.times(0.6)),
                { from: acc1 }
              );
            }

            // wait 0.9 year
            await moneyMarketModule.timePass(0.9);

            // withdraw deposit
            await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
              from: acc0
            });

            // verify earned interest
            const acc1BeforeBalance = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc1)
            );
            // note: because 100% was withdrawn, expect the funding ID to be 2
            await baseContracts.fundingMultitoken.withdrawDividend(
              2,
              baseContracts.stablecoin.address,
              {
                from: acc1
              }
            );
            const actualInterestAmount = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc1)
            ).minus(acc1BeforeBalance);
            const newTotalPrincipal = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              0.9 * Base.YEAR_IN_SEC,
              false
            ).plus(depositAmount);
            const expectedInterestAmount = newTotalPrincipal
              .times(INIT_INTEREST_RATE)
              .times(0.6)
              .times(0.9);
            Base.assertEpsilonEq(
              actualInterestAmount,
              expectedInterestAmount,
              "funding interest earned incorrect"
            );
          });

          it("fund 90%, wait, withdraw 99%, topup, fund 90%", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // acc1 funds 90%
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.INF,
              {
                from: acc1
              }
            );
            const deficitAmount = BigNumber(
              (await baseContracts.dInterestPool.surplusOfDeposit.call(1))
                .surplusAmount
            );
            await baseContracts.dInterestPool.fund(
              1,
              Base.num2str(deficitAmount.times(0.9)),
              { from: acc1 }
            );

            // withdraw 99%
            const depositVirtualTokenTotalSupply = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              true
            ).plus(depositAmount);
            await baseContracts.dInterestPool.withdraw(
              1,
              Base.num2str(depositVirtualTokenTotalSupply.times(0.99)),
              true,
              { from: acc0 }
            );

            // verify received interest + refund
            const totalPrincipal = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            ).plus(depositAmount);
            {
              const acc1BeforeBalance = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc1)
              );
              await baseContracts.fundingMultitoken.withdrawDividend(
                1,
                baseContracts.stablecoin.address,
                {
                  from: acc1
                }
              );
              const actualReceivedAmount = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc1)
              ).minus(acc1BeforeBalance);
              const estimatedLostInterest = totalPrincipal
                .times(INIT_INTEREST_RATE)
                .times(0.89);
              const maxRefundAmount = deficitAmount.times(0.89);
              const expectedRefundAmount = BigNumber.min(
                estimatedLostInterest,
                maxRefundAmount
              );
              Base.assertEpsilonEq(
                actualReceivedAmount,
                expectedRefundAmount,
                "funding refund incorrect"
              );
            }

            // verify deficit
            {
              const deficitAmount = BigNumber(
                (await baseContracts.dInterestPool.surplusOfDeposit.call(1))
                  .surplusAmount
              );
              Base.assertEpsilonEq(
                deficitAmount,
                0,
                "deficit after withdraw incorrect"
              );
            }

            // topup
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            await baseContracts.dInterestPool.topupDeposit(
              1,
              Base.num2str(depositAmount),
              {
                from: acc0
              }
            );

            // verify deficit
            {
              const deficitAmount = BigNumber(
                (await baseContracts.dInterestPool.surplusOfDeposit.call(1))
                  .surplusAmount
              );
              const expectedDeficitAmount = Base.calcInterestAmount(
                depositAmount,
                INIT_INTEREST_RATE_PER_SECOND,
                Base.YEAR_IN_SEC,
                false
              );
              Base.assertEpsilonEq(
                deficitAmount,
                expectedDeficitAmount,
                "deficit after topup incorrect"
              );
            }

            // acc1 funds 90%
            {
              await baseContracts.stablecoin.approve(
                baseContracts.dInterestPool.address,
                Base.INF,
                {
                  from: acc1
                }
              );
              const deficitAmount = BigNumber(
                (await baseContracts.dInterestPool.surplusOfDeposit.call(1))
                  .surplusAmount
              );
              await baseContracts.dInterestPool.fund(
                1,
                Base.num2str(deficitAmount.times(0.9)),
                { from: acc1 }
              );
            }

            // wait 1 year
            await moneyMarketModule.timePass(1);

            // withdraw deposit
            await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
              from: acc0
            });

            // verify earned interest
            const acc1BeforeBalance = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc1)
            );
            await baseContracts.fundingMultitoken.withdrawDividend(
              1,
              baseContracts.stablecoin.address,
              {
                from: acc1
              }
            );
            const actualInterestAmount = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc1)
            ).minus(acc1BeforeBalance);
            const expectedInterestAmount = totalPrincipal
              .times(INIT_INTEREST_RATE)
              .times(0.91);
            Base.assertEpsilonEq(
              actualInterestAmount,
              expectedInterestAmount,
              "funding interest earned incorrect"
            );
          });
        });
      });

      describe("payInterestToFunders", () => {
        context("happy path", () => {
          it("single deposit, two payouts", async () => {
            const depositAmount = 10 * Base.STABLECOIN_PRECISION;

            // acc0 deposits stablecoin into the DInterest pool for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              blockNow + Base.YEAR_IN_SEC,
              { from: acc0 }
            );

            // Fund deficit using acc2
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.INF,
              {
                from: acc2
              }
            );
            await baseContracts.dInterestPool.fund(1, Base.INF, { from: acc2 });

            // Wait 0.3 year
            await moneyMarketModule.timePass(0.3);

            // Payout interest
            await baseContracts.dInterestPool.payInterestToFunders(1, {
              from: acc2
            });

            // Wait 0.7 year
            await moneyMarketModule.timePass(0.7);

            // Payout interest
            await baseContracts.dInterestPool.payInterestToFunders(1, {
              from: acc2
            });

            // Withdraw deposit
            await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
              from: acc0
            });

            // Redeem interest
            const beforeBalance = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc2)
            );
            await baseContracts.fundingMultitoken.withdrawDividend(
              1,
              baseContracts.stablecoin.address,
              {
                from: acc2
              }
            );

            // Check interest received
            const actualInterestReceived = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc2)
            ).minus(beforeBalance);
            const totalPrincipal = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            ).plus(depositAmount);
            const interestExpected = totalPrincipal.times(INIT_INTEREST_RATE);
            Base.assertEpsilonEq(
              actualInterestReceived,
              interestExpected,
              "interest received incorrect"
            );
          });
        });

        context("edge cases", () => {});
      });

      describe("calculateInterestAmount", () => {
        it("one year deposit", async () => {
          const depositAmount = 10 * Base.STABLECOIN_PRECISION;
          const depositTime = 1 * Base.YEAR_IN_SEC;
          const expectedInterestAmount = Base.calcInterestAmount(
            depositAmount,
            INIT_INTEREST_RATE_PER_SECOND,
            depositTime,
            false
          );
          const actualInterestAmount = await baseContracts.dInterestPool.calculateInterestAmount.call(
            depositAmount,
            depositTime
          );
          Base.assertEpsilonEq(
            actualInterestAmount,
            expectedInterestAmount,
            "interest amount incorrect"
          );
        });

        it("half year deposit", async () => {
          const depositAmount = 10 * Base.STABLECOIN_PRECISION;
          const depositTime = 0.5 * Base.YEAR_IN_SEC;
          const expectedInterestAmount = Base.calcInterestAmount(
            depositAmount,
            INIT_INTEREST_RATE_PER_SECOND,
            depositTime,
            false
          );
          const actualInterestAmount = await baseContracts.dInterestPool.calculateInterestAmount.call(
            depositAmount,
            depositTime
          );
          Base.assertEpsilonEq(
            actualInterestAmount,
            expectedInterestAmount,
            "interest amount incorrect"
          );
        });

        it("one day deposit", async () => {
          const depositAmount = 10 * Base.STABLECOIN_PRECISION;
          const depositTime = 24 * 60 * 60;
          const expectedInterestAmount = Base.calcInterestAmount(
            depositAmount,
            INIT_INTEREST_RATE_PER_SECOND,
            depositTime,
            false
          );
          const actualInterestAmount = await baseContracts.dInterestPool.calculateInterestAmount.call(
            depositAmount,
            depositTime
          );
          Base.assertEpsilonEq(
            actualInterestAmount,
            expectedInterestAmount,
            "interest amount incorrect"
          );
        });

        it("0 time deposit", async () => {
          const depositAmount = 10 * Base.STABLECOIN_PRECISION;
          const depositTime = 0;
          const expectedInterestAmount = Base.calcInterestAmount(
            depositAmount,
            INIT_INTEREST_RATE_PER_SECOND,
            depositTime,
            false
          );
          const actualInterestAmount = await baseContracts.dInterestPool.calculateInterestAmount.call(
            depositAmount,
            depositTime
          );
          Base.assertEpsilonEq(
            actualInterestAmount,
            expectedInterestAmount,
            "interest amount incorrect"
          );
        });
      });

      describe("totalInterestOwedToFunders", () => {
        context("happy path", () => {
          it("single deposit", async () => {
            const depositAmount = 10 * Base.STABLECOIN_PRECISION;

            // acc0 deposits for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              blockNow + Base.YEAR_IN_SEC,
              { from: acc0 }
            );

            // Fund deficit using acc2
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.INF,
              {
                from: acc2
              }
            );
            await baseContracts.dInterestPool.fund(1, Base.INF, { from: acc2 });

            // Wait 1 year
            await moneyMarketModule.timePass(1);

            // Surplus should be zero, because the interest owed to funders should be deducted from surplus
            const surplusObj = await baseContracts.dInterestPool.surplus.call();
            Base.assertEpsilonEq(0, surplusObj.surplusAmount, "surplus not 0");

            // totalInterestOwedToFunders() should return the interest generated by the deposit
            const totalInterestOwedToFunders = await baseContracts.dInterestPool.totalInterestOwedToFunders.call();
            const totalPrincipal = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            ).plus(depositAmount);
            const interestExpected = totalPrincipal.times(INIT_INTEREST_RATE);
            Base.assertEpsilonEq(
              totalInterestOwedToFunders,
              interestExpected,
              "interest owed to funders not correct"
            );
          });
        });

        context("edge cases", () => {});
      });

      describe("surplus", () => {
        const depositAmount = 10 * Base.STABLECOIN_PRECISION;

        it("single deposit", async () => {
          // acc0 deposits for 1 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // check surplus
          const surplusObj = await baseContracts.dInterestPool.surplus.call();
          const surplusAmount = BigNumber(surplusObj.surplusAmount);
          assert(surplusObj.isNegative, "surplus not negative");
          const expectedDeficit = Base.calcInterestAmount(
            depositAmount,
            INIT_INTEREST_RATE_PER_SECOND,
            Base.YEAR_IN_SEC,
            false
          );
          Base.assertEpsilonEq(
            surplusAmount,
            expectedDeficit,
            "surplus amount incorrect"
          );

          // wait 0.5 year
          await moneyMarketModule.timePass(0.5);

          // check surplus
          {
            const surplusObj = await baseContracts.dInterestPool.surplus.call();
            const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
              surplusObj.isNegative ? -1 : 1
            );
            const expectedSurplus = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            )
              .minus(depositAmount * INIT_INTEREST_RATE * 0.5)
              .times(-1);
            Base.assertEpsilonEq(
              surplusAmount,
              expectedSurplus,
              "surplus amount incorrect"
            );
          }
        });

        it("two deposits", async () => {
          // acc0 deposits for 1 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // acc0 deposits for 0.5 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + 0.5 * Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // check surplus
          const surplusObj = await baseContracts.dInterestPool.surplus.call();
          const surplusAmount = BigNumber(surplusObj.surplusAmount);
          assert(surplusObj.isNegative, "surplus not negative");
          const expectedDeficit = Base.calcInterestAmount(
            depositAmount,
            INIT_INTEREST_RATE_PER_SECOND,
            Base.YEAR_IN_SEC,
            false
          ).plus(
            Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              0.5 * Base.YEAR_IN_SEC,
              false
            )
          );
          Base.assertEpsilonEq(
            surplusAmount,
            expectedDeficit,
            "surplus amount incorrect"
          );

          // wait 0.5 year
          await moneyMarketModule.timePass(0.5);

          // check surplus
          {
            const surplusObj = await baseContracts.dInterestPool.surplus.call();
            const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
              surplusObj.isNegative ? -1 : 1
            );
            const expectedSurplus = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            )
              .plus(
                Base.calcInterestAmount(
                  depositAmount,
                  INIT_INTEREST_RATE_PER_SECOND,
                  0.5 * Base.YEAR_IN_SEC,
                  false
                )
              )
              .minus(2 * depositAmount * INIT_INTEREST_RATE * 0.5)
              .times(-1);
            Base.assertEpsilonEq(
              surplusAmount,
              expectedSurplus,
              "surplus amount incorrect"
            );
          }
        });

        it("two deposits at different times", async () => {
          // acc0 deposits for 1 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          let blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // wait 0.2 year
          await moneyMarketModule.timePass(0.2);

          // acc0 deposits for 0.5 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + 0.5 * Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // check surplus
          const surplusObj = await baseContracts.dInterestPool.surplus.call();
          const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
            surplusObj.isNegative ? -1 : 1
          );
          const expectedSurplus = Base.calcInterestAmount(
            depositAmount,
            INIT_INTEREST_RATE_PER_SECOND,
            Base.YEAR_IN_SEC,
            false
          )
            .plus(
              Base.calcInterestAmount(
                depositAmount,
                INIT_INTEREST_RATE_PER_SECOND,
                0.5 * Base.YEAR_IN_SEC,
                false
              )
            )
            .minus(depositAmount * INIT_INTEREST_RATE * 0.2)
            .times(-1);
          Base.assertEpsilonEq(
            surplusAmount,
            expectedSurplus,
            "surplus amount incorrect"
          );

          // wait 0.5 year
          await moneyMarketModule.timePass(0.5);

          // check surplus
          {
            const surplusObj = await baseContracts.dInterestPool.surplus.call();
            const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
              surplusObj.isNegative ? -1 : 1
            );
            const expectedSurplus = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            )
              .plus(
                Base.calcInterestAmount(
                  depositAmount,
                  INIT_INTEREST_RATE_PER_SECOND,
                  0.5 * Base.YEAR_IN_SEC,
                  false
                )
              )
              .minus(depositAmount * INIT_INTEREST_RATE * 0.2)
              .minus(
                depositAmount *
                  INIT_INTEREST_RATE *
                  (1 + 0.2 * INIT_INTEREST_RATE) *
                  0.5
              )
              .minus(depositAmount * INIT_INTEREST_RATE * 0.5)
              .times(-1);
            Base.assertEpsilonEq(
              surplusAmount,
              expectedSurplus,
              "surplus amount incorrect"
            );
          }
        });

        it("should be 0 after deposit & early withdraw", async () => {
          // acc0 deposits for 1 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // early withdraw
          await baseContracts.dInterestPool.withdraw(1, Base.INF, true, {
            from: acc0
          });

          // check surplus
          const surplusObj = await baseContracts.dInterestPool.surplus.call();
          const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
            surplusObj.isNegative ? -1 : 1
          );
          Base.assertEpsilonEq(surplusAmount, 0, "surplus amount incorrect");
        });

        it("should be 0 after deposit & fund", async () => {
          // acc0 deposits for 1 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // Fund deficit using acc2
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.INF,
            {
              from: acc2
            }
          );
          await baseContracts.dInterestPool.fund(1, Base.INF, { from: acc2 });

          // check surplus
          const surplusObj = await baseContracts.dInterestPool.surplus.call();
          const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
            surplusObj.isNegative ? -1 : 1
          );
          Base.assertEpsilonEq(surplusAmount, 0, "surplus amount incorrect");
        });
      });

      describe("rawSurplusOfDeposit", () => {
        const depositAmount = 10 * Base.STABLECOIN_PRECISION;

        it("simple deposit", async () => {
          // acc0 deposits for 1 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // check surplus
          const surplusObj = await baseContracts.dInterestPool.rawSurplusOfDeposit.call(
            1
          );
          const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
            surplusObj.isNegative ? -1 : 1
          );
          const expectedSurplus = Base.calcInterestAmount(
            depositAmount,
            INIT_INTEREST_RATE_PER_SECOND,
            Base.YEAR_IN_SEC,
            false
          ).times(-1);
          Base.assertEpsilonEq(
            surplusAmount,
            expectedSurplus,
            "surplus amount incorrect"
          );

          // wait 0.5 year
          await moneyMarketModule.timePass(0.5);

          // check surplus
          {
            const surplusObj = await baseContracts.dInterestPool.rawSurplusOfDeposit.call(
              1
            );
            const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
              surplusObj.isNegative ? -1 : 1
            );
            const expectedSurplus = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            )
              .minus(depositAmount * INIT_INTEREST_RATE * 0.5)
              .times(-1);
            Base.assertEpsilonEq(
              surplusAmount,
              expectedSurplus,
              "surplus amount incorrect"
            );
          }
        });

        it("should be 0 after deposit & early withdraw", async () => {
          // acc0 deposits for 1 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // early withdraw
          await baseContracts.dInterestPool.withdraw(1, Base.INF, true, {
            from: acc0
          });

          // check surplus
          const surplusObj = await baseContracts.dInterestPool.rawSurplusOfDeposit.call(
            1
          );
          const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
            surplusObj.isNegative ? -1 : 1
          );
          Base.assertEpsilonEq(surplusAmount, 0, "surplus amount incorrect");
        });

        it("should be the same after deposit & early withdraw & topup", async () => {
          // acc0 deposits for 1 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // early withdraw
          await baseContracts.dInterestPool.withdraw(1, Base.INF, true, {
            from: acc0
          });

          // topup
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          await baseContracts.dInterestPool.topupDeposit(
            1,
            Base.num2str(depositAmount),
            {
              from: acc0
            }
          );

          // check surplus
          const surplusObj = await baseContracts.dInterestPool.rawSurplusOfDeposit.call(
            1
          );
          const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
            surplusObj.isNegative ? -1 : 1
          );
          const expectedSurplus = Base.calcInterestAmount(
            depositAmount,
            INIT_INTEREST_RATE_PER_SECOND,
            Base.YEAR_IN_SEC,
            false
          ).times(-1);
          Base.assertEpsilonEq(
            surplusAmount,
            expectedSurplus,
            "surplus amount incorrect"
          );
        });
      });

      describe("surplusOfDeposit", () => {
        const depositAmount = 10 * Base.STABLECOIN_PRECISION;

        it("simple deposit", async () => {
          // acc0 deposits for 1 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // check surplus
          const surplusObj = await baseContracts.dInterestPool.surplusOfDeposit.call(
            1
          );
          const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
            surplusObj.isNegative ? -1 : 1
          );
          const expectedSurplus = Base.calcInterestAmount(
            depositAmount,
            INIT_INTEREST_RATE_PER_SECOND,
            Base.YEAR_IN_SEC,
            false
          ).times(-1);
          Base.assertEpsilonEq(
            surplusAmount,
            expectedSurplus,
            "surplus amount incorrect"
          );

          // wait 0.5 year
          await moneyMarketModule.timePass(0.5);

          // check surplus
          {
            const surplusObj = await baseContracts.dInterestPool.surplusOfDeposit.call(
              1
            );
            const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
              surplusObj.isNegative ? -1 : 1
            );
            const expectedSurplus = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            )
              .minus(depositAmount * INIT_INTEREST_RATE * 0.5)
              .times(-1);
            Base.assertEpsilonEq(
              surplusAmount,
              expectedSurplus,
              "surplus amount incorrect"
            );
          }
        });

        it("should be 0 after deposit & early withdraw", async () => {
          // acc0 deposits for 1 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // early withdraw
          await baseContracts.dInterestPool.withdraw(1, Base.INF, true, {
            from: acc0
          });

          // check surplus
          const surplusObj = await baseContracts.dInterestPool.surplusOfDeposit.call(
            1
          );
          const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
            surplusObj.isNegative ? -1 : 1
          );
          Base.assertEpsilonEq(surplusAmount, 0, "surplus amount incorrect");
        });

        it("should be the same after deposit & early withdraw & topup", async () => {
          // acc0 deposits for 1 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // early withdraw
          await baseContracts.dInterestPool.withdraw(1, Base.INF, true, {
            from: acc0
          });

          // topup
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          await baseContracts.dInterestPool.topupDeposit(
            1,
            Base.num2str(depositAmount),
            {
              from: acc0
            }
          );

          // check surplus
          const surplusObj = await baseContracts.dInterestPool.surplusOfDeposit.call(
            1
          );
          const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
            surplusObj.isNegative ? -1 : 1
          );
          const expectedSurplus = Base.calcInterestAmount(
            depositAmount,
            INIT_INTEREST_RATE_PER_SECOND,
            Base.YEAR_IN_SEC,
            false
          ).times(-1);
          Base.assertEpsilonEq(
            surplusAmount,
            expectedSurplus,
            "surplus amount incorrect"
          );
        });

        it("should be 0 after fully funded", async () => {
          // acc0 deposits for 1 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // Fund deficit using acc2
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.INF,
            {
              from: acc2
            }
          );
          await baseContracts.dInterestPool.fund(1, Base.INF, { from: acc2 });

          // check surplus
          const surplusObj = await baseContracts.dInterestPool.surplusOfDeposit.call(
            1
          );
          const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
            surplusObj.isNegative ? -1 : 1
          );
          Base.assertEpsilonEq(surplusAmount, 0, "surplus amount incorrect");
        });

        it("should be correct after partially funded", async () => {
          // acc0 deposits for 1 year
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            blockNow + Base.YEAR_IN_SEC,
            { from: acc0 }
          );

          // Fund 30% deficit using acc2
          const deficitAmount = BigNumber(
            (await baseContracts.dInterestPool.surplusOfDeposit.call(1))
              .surplusAmount
          );
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.INF,
            {
              from: acc2
            }
          );
          await baseContracts.dInterestPool.fund(
            1,
            Base.num2str(deficitAmount.times(0.3)),
            {
              from: acc2
            }
          );

          // check surplus
          const surplusObj = await baseContracts.dInterestPool.surplusOfDeposit.call(
            1
          );
          const surplusAmount = BigNumber(surplusObj.surplusAmount).times(
            surplusObj.isNegative ? -1 : 1
          );
          const expectedSurplus = Base.calcInterestAmount(
            depositAmount,
            INIT_INTEREST_RATE_PER_SECOND,
            Base.YEAR_IN_SEC,
            false
          )
            .times(0.7)
            .times(-1);
          Base.assertEpsilonEq(
            surplusAmount,
            expectedSurplus,
            "surplus amount incorrect"
          );
        });
      });

      describe("withdrawableAmountOfDeposit", () => {
        context("happy path", () => {
          it("simple deposit", async () => {
            const depositAmount = 10 * Base.STABLECOIN_PRECISION;

            // acc0 deposits stablecoin into the DInterest pool for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              blockNow + Base.YEAR_IN_SEC,
              { from: acc0 }
            );

            // Verify withdrawableAmountOfDeposit
            {
              const withdrawableAmountOfDeposit = BigNumber(
                (
                  await baseContracts.dInterestPool.withdrawableAmountOfDeposit(
                    1,
                    Base.INF
                  )
                ).withdrawableAmount
              );
              const expectedAmount = Base.applyEarlyWithdrawFee(depositAmount);
              Base.assertEpsilonEq(
                withdrawableAmountOfDeposit,
                expectedAmount,
                "withdrawableAmountOfDeposit incorrect"
              );
            }

            // Wait 1 year
            await moneyMarketModule.timePass(1);

            // Verify withdrawableAmountOfDeposit
            {
              const withdrawableAmountOfDeposit = BigNumber(
                (
                  await baseContracts.dInterestPool.withdrawableAmountOfDeposit(
                    1,
                    Base.INF
                  )
                ).withdrawableAmount
              );
              const expectedAmount = Base.calcInterestAmount(
                depositAmount,
                INIT_INTEREST_RATE_PER_SECOND,
                Base.YEAR_IN_SEC,
                true
              ).plus(depositAmount);
              Base.assertEpsilonEq(
                withdrawableAmountOfDeposit,
                expectedAmount,
                "withdrawableAmountOfDeposit incorrect"
              );
            }

            // Withdraw
            await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
              from: acc0
            });

            // Verify withdrawableAmountOfDeposit
            {
              const withdrawableAmountOfDeposit = BigNumber(
                (
                  await baseContracts.dInterestPool.withdrawableAmountOfDeposit(
                    1,
                    Base.INF
                  )
                ).withdrawableAmount
              );
              Base.assertEpsilonEq(
                withdrawableAmountOfDeposit,
                0,
                "withdrawableAmountOfDeposit incorrect"
              );
            }
          });
        });

        context("edge cases", () => {});
      });

      describe("accruedInterestOfFunding", () => {
        context("happy path", () => {
          it("single deposit, two payouts", async () => {
            const depositAmount = 10 * Base.STABLECOIN_PRECISION;

            // acc0 deposits stablecoin into the DInterest pool for 1 year
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.num2str(depositAmount),
              { from: acc0 }
            );
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              blockNow + Base.YEAR_IN_SEC,
              { from: acc0 }
            );

            // Fund deficit using acc2
            await baseContracts.stablecoin.approve(
              baseContracts.dInterestPool.address,
              Base.INF,
              {
                from: acc2
              }
            );
            await baseContracts.dInterestPool.fund(1, Base.INF, { from: acc2 });

            // Wait 0.3 year
            await moneyMarketModule.timePass(0.3);

            // Check accrued interest
            {
              const actualAccruedInterest = BigNumber(
                await baseContracts.dInterestPool.accruedInterestOfFunding.call(
                  1
                )
              );
              const expectedAccruedInterest = Base.calcInterestAmount(
                depositAmount,
                INIT_INTEREST_RATE_PER_SECOND,
                Base.YEAR_IN_SEC,
                false
              )
                .plus(depositAmount)
                .times(INIT_INTEREST_RATE)
                .times(0.3);
              Base.assertEpsilonEq(
                actualAccruedInterest,
                expectedAccruedInterest,
                "accrued interest incorrect"
              );
            }

            // Payout interest
            await baseContracts.dInterestPool.payInterestToFunders(1, {
              from: acc2
            });

            // Check accrued interest
            {
              const actualAccruedInterest = BigNumber(
                await baseContracts.dInterestPool.accruedInterestOfFunding.call(
                  1
                )
              );
              const expectedAccruedInterest = 0;
              Base.assertEpsilonEq(
                actualAccruedInterest,
                expectedAccruedInterest,
                "accrued interest incorrect"
              );
            }

            // Wait 0.7 year
            await moneyMarketModule.timePass(0.7);

            // Check accrued interest
            {
              const actualAccruedInterest = BigNumber(
                await baseContracts.dInterestPool.accruedInterestOfFunding.call(
                  1
                )
              );
              const expectedAccruedInterest = Base.calcInterestAmount(
                depositAmount,
                INIT_INTEREST_RATE_PER_SECOND,
                Base.YEAR_IN_SEC,
                false
              )
                .plus(depositAmount)
                .times(INIT_INTEREST_RATE)
                .times(0.7);
              Base.assertEpsilonEq(
                actualAccruedInterest,
                expectedAccruedInterest,
                "accrued interest incorrect"
              );
            }

            // Payout interest
            await baseContracts.dInterestPool.payInterestToFunders(1, {
              from: acc2
            });

            // Check accrued interest
            {
              const actualAccruedInterest = BigNumber(
                await baseContracts.dInterestPool.accruedInterestOfFunding.call(
                  1
                )
              );
              const expectedAccruedInterest = 0;
              Base.assertEpsilonEq(
                actualAccruedInterest,
                expectedAccruedInterest,
                "accrued interest incorrect"
              );
            }
          });
        });

        context("edge cases", () => {});
      });
    });
  }
});
