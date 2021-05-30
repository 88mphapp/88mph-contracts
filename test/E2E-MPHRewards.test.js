const Base = require("./base");
const BigNumber = require("bignumber.js");
const { assert } = require("hardhat");

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
  const INIT_INTEREST_RATE_PER_SECOND = 0.1 / Base.YEAR_IN_SEC; // 10% APY
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

        it("early withdraw gives reward earned so far", async () => {
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
          await baseContracts.stablecoin.approve(
            baseContracts.dInterestPool.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
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
          await baseContracts.stablecoin.approve(
            pool1.address,
            Base.num2str(depositAmount),
            { from: acc0 }
          );
          await pool1.deposit(
            Base.num2str(depositAmount),
            Base.num2str(blockNow + Base.YEAR_IN_SEC),
            { from: acc0 }
          );

          // acc1 deposits in pool2 for 1 year
          await baseContracts.stablecoin.approve(
            pool2.address,
            Base.num2str(depositAmount),
            { from: acc1 }
          );
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
        it("works", async () => {});
      });

      describe("dev rewards", () => {
        it("works", async () => {});
      });

      describe("gov rewards", () => {
        it("works", async () => {});
      });
    });
  }
});
