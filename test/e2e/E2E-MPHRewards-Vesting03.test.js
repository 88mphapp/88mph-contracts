const Base = require("../base");
const BigNumber = require("bignumber.js");

contract("E2E-MPHRewards-Vesting03", (accounts) => {
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
  const mphRewardAmount = 100 * Base.PRECISION;
  const DURATION = Base.YEAR_IN_SEC;

  for (const moduleInfo of Base.moneyMarketModuleList) {
    const moneyMarketModule = moduleInfo.moduleGenerator();
    context(`Money market: ${moduleInfo.name}`, () => {
      beforeEach(async () => {
        baseContracts = await Base.setupTest(accounts, moneyMarketModule);

        // deploy Vesting03
        baseContracts.vesting03 = await Base.Vesting03.new();
        await baseContracts.vesting03.initialize(
          baseContracts.mph.address,
          "Vested MPH",
          "veMPH",
          { from: acc0 }
        );
        await baseContracts.vesting03.setMPHMinter(
          baseContracts.mphMinter.address,
          { from: acc0 }
        );
        await baseContracts.mphMinter.setVesting02(
          baseContracts.vesting03.address,
          { from: govTreasury }
        );
        await baseContracts.vesting03.updateDuration(DURATION, { from: acc0 });
        await baseContracts.vesting03.setRewardDistributor(acc0, true, {
          from: acc0,
        });

        // deploy Forwarder
        await baseContracts.vesting03.deployForwarderOfPool(
          baseContracts.dInterestPool.address,
          { from: acc0 }
        );
        const forwarderAddress = await baseContracts.vesting03.forwarderOfPool(
          baseContracts.dInterestPool.address,
          { from: acc0 }
        );

        // mint MPH to forwarder and notify
        await baseContracts.mphMinter.grantRole(Base.CONVERTER_ROLE, acc0, {
          from: govTreasury,
        });
        await baseContracts.mphMinter.converterMint(
          forwarderAddress,
          Base.num2str(mphRewardAmount),
          {
            from: acc0,
          }
        );
        await baseContracts.vesting03.notifyRewardAmount(
          baseContracts.dInterestPool.address,
          Base.num2str(mphRewardAmount),
          { from: acc0 }
        );
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

          await baseContracts.vesting03.withdraw(1, { from: acc0 });

          // check reward amount
          const actualRewardAmount = BigNumber(
            await baseContracts.mph.balanceOf(acc0)
          ).minus(beforeMPHBalance);
          const expectedRewardAmount = BigNumber(mphRewardAmount);
          Base.assertEpsilonEq(
            actualRewardAmount,
            expectedRewardAmount,
            "deposit reward incorrect"
          );
        });

        it("reward doesn't accrue after period finish", async () => {
          // acc0 deposits for 2 year
          const blockNow = await Base.latestBlockTimestamp();
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            Base.num2str(blockNow + Base.YEAR_IN_SEC),
            { from: acc0 }
          );

          // wait for maturation
          await moneyMarketModule.timePass(2);

          // claim rewards
          const beforeMPHBalance = BigNumber(
            await baseContracts.mph.balanceOf(acc0)
          );

          await baseContracts.vesting03.withdraw(1, { from: acc0 });

          // check reward amount
          const actualRewardAmount = BigNumber(
            await baseContracts.mph.balanceOf(acc0)
          ).minus(beforeMPHBalance);
          const expectedRewardAmount = BigNumber(mphRewardAmount);
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
            await baseContracts.vesting03.withdraw(1, { from: acc0 });

            // check reward amount
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(mphRewardAmount).times(0.5);
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
            from: acc0,
          });

          {
            // claim rewards
            const beforeMPHBalance = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            );
            await baseContracts.vesting03.withdraw(1, { from: acc0 });

            // check reward amount
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(mphRewardAmount).times(0.5);
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

          // acc1 deposits the same amount for 1 year
          await baseContracts.dInterestPool.deposit(
            Base.num2str(depositAmount),
            Base.num2str(blockNow + Base.YEAR_IN_SEC),
            { from: acc1 }
          );

          // wait for half a year
          await moneyMarketModule.timePass(0.5);

          {
            // claim rewards
            const beforeMPHBalance = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            );
            await baseContracts.vesting03.withdraw(1, { from: acc0 });

            // check reward amount
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(mphRewardAmount).div(4);
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
            await baseContracts.vesting03.withdraw(1, { from: acc0 });

            // check reward amount
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(mphRewardAmount)
              .div(2)
              .times(2 / 3);
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

          // deploy Forwarder
          await baseContracts.vesting03.deployForwarderOfPool(pool2.address, {
            from: acc0,
          });
          const forwarderAddress =
            await baseContracts.vesting03.forwarderOfPool(pool2.address, {
              from: acc0,
            });

          // mint MPH to forwarder and notify
          await baseContracts.mphMinter.grantRole(Base.CONVERTER_ROLE, acc0, {
            from: govTreasury,
          });
          await baseContracts.mphMinter.converterMint(
            forwarderAddress,
            Base.num2str(mphRewardAmount),
            {
              from: acc0,
            }
          );
          await baseContracts.vesting03.notifyRewardAmount(
            pool2.address,
            Base.num2str(mphRewardAmount),
            { from: acc0 }
          );

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
            await baseContracts.vesting03.withdraw(1, { from: acc0 });

            // check reward amount
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc0)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(mphRewardAmount);
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
            await baseContracts.vesting03.withdraw(2, { from: acc1 });

            // check reward amount
            const actualRewardAmount = BigNumber(
              await baseContracts.mph.balanceOf(acc1)
            ).minus(beforeMPHBalance);
            const expectedRewardAmount = BigNumber(mphRewardAmount);
            Base.assertEpsilonEq(
              actualRewardAmount,
              expectedRewardAmount,
              "deposit reward incorrect"
            );
          }
        });
      });
    });
  }
});
