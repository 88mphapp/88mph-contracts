const Base = require("../base");
const BigNumber = require("bignumber.js");

contract("E2E-MPHRewards", accounts => {
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
  const INIT_INTEREST_RATE_PER_SECOND = Math.log2(
    Math.pow(INIT_INTEREST_RATE + 1, 1 / Base.YEAR_IN_SEC)
  );
  const depositAmount = 100 * Base.STABLECOIN_PRECISION;

  for (const moduleInfo of Base.moneyMarketModuleList) {
    const moneyMarketModule = moduleInfo.moduleGenerator();
    context(`Money market: ${moduleInfo.name}`, () => {
      beforeEach(async () => {
        baseContracts = await Base.setupTest(accounts, moneyMarketModule);
      });

      describe("depositor rewards", () => {
        it("works", async () => {
          // acc0 deposits for 1 year
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            Base.num2str(blockNow + Base.YEAR_IN_SEC),
            { from: acc0 }
          );

          // wait for maturation
          await moneyMarketModule.timePass(1);

          // claim rewards
          const beforeMPHBalance = BigNumber(
            await baseContracts.mph.balanceOf(acc0)
          );
          await baseContracts.vesting02.withdraw(1, { from: acc0 });

          // check reward amount
          const actualRewardAmount = BigNumber(
            await baseContracts.mph.balanceOf(acc0)
          ).minus(beforeMPHBalance);
          const expectedRewardAmount = BigNumber(
            Base.PoolDepositorRewardMintMultiplier
          )
            .times(depositAmount)
            .times(Base.YEAR_IN_SEC)
            .div(Base.PRECISION);
          Base.assertEpsilonEq(
            actualRewardAmount,
            expectedRewardAmount,
            "deposit reward incorrect"
          );
        });

        it("doesn't give more reward after maturation", async () => {
          // acc0 deposits for 1 year
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            Base.num2str(blockNow + Base.YEAR_IN_SEC),
            { from: acc0 }
          );

          // wait for long after maturation
          await moneyMarketModule.timePass(2);

          // claim rewards
          const beforeMPHBalance = BigNumber(
            await baseContracts.mph.balanceOf(acc0)
          );
          await baseContracts.vesting02.withdraw(1, { from: acc0 });

          // check reward amount
          const actualRewardAmount = BigNumber(
            await baseContracts.mph.balanceOf(acc0)
          ).minus(beforeMPHBalance);
          const expectedRewardAmount = BigNumber(
            Base.PoolDepositorRewardMintMultiplier
          )
            .times(depositAmount)
            .times(Base.YEAR_IN_SEC)
            .div(Base.PRECISION);
          Base.assertEpsilonEq(
            actualRewardAmount,
            expectedRewardAmount,
            "deposit reward incorrect"
          );
        });

        it("early withdraw gives reward earned so far", async () => {
          // acc0 deposits for 1 year
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            Base.num2str(blockNow + Base.YEAR_IN_SEC),
            { from: acc0 }
          );

          // wait for half a year
          await moneyMarketModule.timePass(0.5);

          {
            // claim rewards
            const beforeMPHBalance = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            );
            await baseContracts.vesting02.withdraw(1, { from: acc0 });

            // check reward amount
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(
              Base.PoolDepositorRewardMintMultiplier
            )
              .times(depositAmount)
              .times(Base.YEAR_IN_SEC)
              .times(0.5)
              .div(Base.PRECISION);
            Base.assertEpsilonEq(
              actualRewardAmount,
              expectedRewardAmount,
              "deposit reward incorrect"
            );
          }

          // withdraw early
          let virtualTokenTotalSupply = BigNumber(
            (await baseContracts.dInterestPool.getDeposit(1))
              .virtualTokenTotalSupply
          );
          let withdrawVirtualTokenAmount = virtualTokenTotalSupply
            .times(0.5)
            .integerValue();
          await baseContracts.dInterestPool.withdraw(
            1,
            Base.num2str(withdrawVirtualTokenAmount),
            true,
            { from: acc0 }
          );

          // wait for maturation
          await moneyMarketModule.timePass(0.5);

          // withdraw
          await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
            from: acc0
          });

          {
            // claim rewards
            const beforeMPHBalance = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            );
            await baseContracts.vesting02.withdraw(1, { from: acc0 });

            // check reward amount
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(
              Base.PoolDepositorRewardMintMultiplier
            )
              .times(depositAmount)
              .times(0.5)
              .times(Base.YEAR_IN_SEC)
              .times(0.5)
              .div(Base.PRECISION);
            Base.assertEpsilonEq(
              actualRewardAmount,
              expectedRewardAmount,
              "deposit reward incorrect"
            );
          }
        });

        it("topup increases the reward earned after", async () => {
          // acc0 deposits for 1 year
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            Base.num2str(blockNow + Base.YEAR_IN_SEC),
            { from: acc0 }
          );

          // wait for half a year
          await moneyMarketModule.timePass(0.5);

          {
            // claim rewards
            const beforeMPHBalance = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            );
            await baseContracts.vesting02.withdraw(1, { from: acc0 });

            // check reward amount
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(
              Base.PoolDepositorRewardMintMultiplier
            )
              .times(depositAmount)
              .times(Base.YEAR_IN_SEC)
              .times(0.5)
              .div(Base.PRECISION);
            Base.assertEpsilonEq(
              actualRewardAmount,
              expectedRewardAmount,
              "deposit reward incorrect"
            );
          }

          // topup the same amount
          await baseContracts.dInterestPool.topupDeposit(
            1,
            Base.num2str(depositAmount),
            { from: acc0 }
          );

          // wait until maturation
          await moneyMarketModule.timePass(0.5);

          {
            // claim rewards
            const beforeMPHBalance = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            );
            await baseContracts.vesting02.withdraw(1, { from: acc0 });

            // check reward amount
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(
              Base.PoolDepositorRewardMintMultiplier
            )
              .times(depositAmount)
              .times(2)
              .times(Base.YEAR_IN_SEC)
              .times(0.5)
              .div(Base.PRECISION);
            Base.assertEpsilonEq(
              actualRewardAmount,
              expectedRewardAmount,
              "deposit reward incorrect"
            );
          }
        });

        it("works for two pools", async () => {
          // deploy second pool
          const pool1 = baseContracts.dInterestPool;
          const { dInterestPool } = await baseContracts.deployDInterest();
          const pool2 = dInterestPool;
          const blockNow = await Base.latestBlockTimestamp();

          // acc0 deposits in pool1 for 1 year
          await pool1.deposit(
            Base.num2str(depositAmount),
            Base.num2str(blockNow + Base.YEAR_IN_SEC),
            { from: acc0 }
          );

          // acc1 deposits in pool2 for 1 year
          await pool2.deposit(
            Base.num2str(depositAmount),
            Base.num2str(blockNow + Base.YEAR_IN_SEC),
            { from: acc1 }
          );

          // wait for maturation
          await moneyMarketModule.timePass(1);

          // withdraw
          await pool1.withdraw(1, Base.INF, false, { from: acc0 });
          await pool2.withdraw(1, Base.INF, false, { from: acc1 });

          {
            // claim rewards for acc0
            const beforeMPHBalance = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            );
            await baseContracts.vesting02.withdraw(1, { from: acc0 });

            // check reward amount
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(
              Base.PoolDepositorRewardMintMultiplier
            )
              .times(depositAmount)
              .times(Base.YEAR_IN_SEC)
              .div(Base.PRECISION);
            Base.assertEpsilonEq(
              actualRewardAmount,
              expectedRewardAmount,
              "deposit reward incorrect"
            );
          }

          {
            // claim rewards for acc1
            const beforeMPHBalance = BigNumber(
              await baseContracts.mph.balanceOf(acc1)
            );
            await baseContracts.vesting02.withdraw(2, { from: acc1 });

            // check reward amount
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc1)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(
              Base.PoolDepositorRewardMintMultiplier
            )
              .times(depositAmount)
              .times(Base.YEAR_IN_SEC)
              .div(Base.PRECISION);
            Base.assertEpsilonEq(
              actualRewardAmount,
              expectedRewardAmount,
              "deposit reward incorrect"
            );
          }
        });
      });

      describe("funder rewards", () => {
        it("works", async () => {
          // acc0 deposits for 1 year
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            Base.num2str(blockNow + Base.YEAR_IN_SEC),
            { from: acc0 }
          );

          // acc1 funds the deposit
          await baseContracts.dInterestPool.fund(1, Base.INF, { from: acc1 });

          // wait for maturation
          await moneyMarketModule.timePass(1);

          // withdraw deposit
          await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
            from: acc0
          });

          {
            // claim rewards
            const beforeMPHBalance = BigNumber(
              await baseContracts.mph.balanceOf(acc1)
            );
            await baseContracts.fundingMultitoken.withdrawDividend(
              1,
              baseContracts.mph.address,
              { from: acc1 }
            );

            // check reward amount
            const totalPrincipal = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            ).plus(depositAmount);
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc1)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(
              Base.PoolFunderRewardMultiplier
            )
              .times(totalPrincipal)
              .times(INIT_INTEREST_RATE)
              .div(Base.PRECISION);
            Base.assertEpsilonEq(
              actualRewardAmount,
              expectedRewardAmount,
              "funder reward incorrect"
            );
          }
        });

        it("doesn't give more reward after maturation", async () => {
          // acc0 deposits for 1 year
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            Base.num2str(blockNow + Base.YEAR_IN_SEC),
            { from: acc0 }
          );

          // acc1 funds the deposit
          await baseContracts.dInterestPool.fund(1, Base.INF, { from: acc1 });

          // wait for long after maturation
          await moneyMarketModule.timePass(2);

          // withdraw deposit
          await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
            from: acc0
          });

          {
            // claim rewards
            const beforeMPHBalance = BigNumber(
              await baseContracts.mph.balanceOf(acc1)
            );
            await baseContracts.fundingMultitoken.withdrawDividend(
              1,
              baseContracts.mph.address,
              { from: acc1 }
            );

            // check reward amount
            const totalPrincipal = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            ).plus(depositAmount);
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc1)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(
              Base.PoolFunderRewardMultiplier
            )
              .times(totalPrincipal)
              .times(INIT_INTEREST_RATE)
              .div(Base.PRECISION);
            Base.assertEpsilonEq(
              actualRewardAmount,
              expectedRewardAmount,
              "funder reward incorrect"
            );
          }
        });

        it("works for partial funding", async () => {
          const fundProportion = 0.1;
          const maturationProportion = 0.3;

          // acc0 deposits for 1 year
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            Base.num2str(blockNow + Base.YEAR_IN_SEC),
            { from: acc0 }
          );

          // acc1 funds 10% of the deposit
          const deficitAmount = BigNumber(
            (
              await baseContracts.lens.surplusOfDeposit.call(
                baseContracts.dInterestPool.address,
                1
              )
            ).surplusAmount
          );
          await baseContracts.dInterestPool.fund(
            1,
            Base.num2str(deficitAmount.times(fundProportion)),
            { from: acc1 }
          );

          // wait for 30% maturation
          await moneyMarketModule.timePass(maturationProportion);

          // pay out interest
          await baseContracts.dInterestPool.payInterestToFunders(1, {
            from: acc2
          });

          {
            // claim rewards
            const beforeMPHBalance = BigNumber(
              await baseContracts.mph.balanceOf(acc1)
            );
            await baseContracts.fundingMultitoken.withdrawDividend(
              1,
              baseContracts.mph.address,
              { from: acc1 }
            );

            // check reward amount
            const totalPrincipal = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            ).plus(depositAmount);
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc1)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(
              Base.PoolFunderRewardMultiplier
            )
              .times(totalPrincipal)
              .times(INIT_INTEREST_RATE)
              .div(Base.PRECISION)
              .times(fundProportion)
              .times(maturationProportion);
            Base.assertEpsilonEq(
              actualRewardAmount,
              expectedRewardAmount,
              "funder reward incorrect"
            );
          }
        });
      });

      describe("dev rewards", () => {
        it("works for depositor rewards", async () => {
          // acc0 deposits for 1 year
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            Base.num2str(blockNow + Base.YEAR_IN_SEC),
            { from: acc0 }
          );

          // wait for maturation
          await moneyMarketModule.timePass(1);

          // claim rewards
          const beforeMPHBalance = BigNumber(
            await baseContracts.mph.balanceOf(devWallet)
          );
          await baseContracts.vesting02.withdraw(1, { from: acc0 });

          // check reward amount
          const actualRewardAmount = BigNumber(
            await baseContracts.mph.balanceOf(devWallet)
          ).minus(beforeMPHBalance);
          const expectedRewardAmount = BigNumber(
            Base.PoolDepositorRewardMintMultiplier
          )
            .times(depositAmount)
            .times(Base.YEAR_IN_SEC)
            .div(Base.PRECISION)
            .times(Base.DevRewardMultiplier)
            .div(Base.PRECISION);
          Base.assertEpsilonEq(
            actualRewardAmount,
            expectedRewardAmount,
            "deposit dev reward incorrect"
          );
        });

        it("works for funder rewards", async () => {
          // acc0 deposits for 1 year
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            Base.num2str(blockNow + Base.YEAR_IN_SEC),
            { from: acc0 }
          );

          // acc1 funds the deposit
          await baseContracts.dInterestPool.fund(1, Base.INF, { from: acc1 });

          // wait for maturation
          await moneyMarketModule.timePass(1);

          // withdraw deposit
          const beforeMPHBalance = BigNumber(
            await baseContracts.mph.balanceOf(devWallet)
          );
          await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
            from: acc0
          });

          {
            // claim rewards
            await baseContracts.fundingMultitoken.withdrawDividend(
              1,
              baseContracts.mph.address,
              { from: acc1 }
            );

            // check reward amount
            const totalPrincipal = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              false
            ).plus(depositAmount);
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(devWallet)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(
              Base.PoolFunderRewardMultiplier
            )
              .times(totalPrincipal)
              .times(INIT_INTEREST_RATE)
              .div(Base.PRECISION)
              .times(Base.DevRewardMultiplier)
              .div(Base.PRECISION);
            Base.assertEpsilonEq(
              actualRewardAmount,
              expectedRewardAmount,
              "funder dev reward incorrect"
            );
          }
        });
      });

      describe("gov rewards", () => {
        it("works", async () => {
          it("works for depositor rewards", async () => {
            // acc0 deposits for 1 year
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // wait for maturation
            await moneyMarketModule.timePass(1);

            // claim rewards
            const beforeMPHBalance = BigNumber(
              await baseContracts.mph.balanceOf(govTreasury)
            );
            await baseContracts.vesting02.withdraw(1, { from: acc0 });

            // check reward amount
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(govTreasury)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(
              Base.PoolDepositorRewardMintMultiplier
            )
              .times(depositAmount)
              .times(Base.YEAR_IN_SEC)
              .div(Base.PRECISION)
              .times(Base.GovRewardMultiplier)
              .div(Base.PRECISION);
            Base.assertEpsilonEq(
              actualRewardAmount,
              expectedRewardAmount,
              "deposit gov reward incorrect"
            );
          });

          it("works for funder rewards", async () => {
            // acc0 deposits for 1 year
            const blockNow = await Base.latestBlockTimestamp();
            await baseContracts.dInterestPool.deposit(
              Base.num2str(depositAmount),
              Base.num2str(blockNow + Base.YEAR_IN_SEC),
              { from: acc0 }
            );

            // acc1 funds the deposit
            await baseContracts.dInterestPool.fund(1, Base.INF, { from: acc1 });

            // wait for maturation
            await moneyMarketModule.timePass(1);

            // withdraw deposit
            const beforeMPHBalance = BigNumber(
              await baseContracts.mph.balanceOf(govTreasury)
            );
            await baseContracts.dInterestPool.withdraw(1, Base.INF, false, {
              from: acc0
            });

            {
              // claim rewards
              await baseContracts.fundingMultitoken.withdrawDividend(
                1,
                baseContracts.mph.address,
                { from: acc1 }
              );

              // check reward amount
              const totalPrincipal = Base.calcInterestAmount(
                depositAmount,
                INIT_INTEREST_RATE_PER_SECOND,
                Base.YEAR_IN_SEC,
                false
              ).plus(depositAmount);
              const actualRewardAmount = BigNumber(
                await baseContracts.mph.balanceOf(govTreasury)
              ).minus(beforeMPHBalance);
              const expectedRewardAmount = BigNumber(
                Base.PoolFunderRewardMultiplier
              )
                .times(totalPrincipal)
                .times(INIT_INTEREST_RATE)
                .div(Base.PRECISION)
                .times(Base.GovRewardMultiplier)
                .div(Base.PRECISION);
              Base.assertEpsilonEq(
                actualRewardAmount,
                expectedRewardAmount,
                "funder gov reward incorrect"
              );
            }
          });
        });
      });
    });
  }
});
