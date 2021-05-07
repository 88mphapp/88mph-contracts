const Base = require("../base");
const BigNumber = require("bignumber.js");
const { assert, artifacts } = require("hardhat");

const ZeroCouponBond = artifacts.require("ZeroCouponBond");

const assertRevertMessage = (errMessage, expectedErrMessage) => {
  return assert(errMessage.startsWith("VM Exception while processing transaction: revert "+ expectedErrMessage), `Expected "${expectedErrMessage} revert reason but got "${errMessage}"`);
}

contract("ZeroCouponBond", accounts => {
  // Accounts
  const acc0 = accounts[0];
  const acc1 = accounts[1];
  const acc2 = accounts[2];
  const govTreasury = accounts[3];
  const devWallet = accounts[4];

  // Contract instances
  let baseContracts;
  let zeroCouponBond;

  // Constants
  const INIT_INTEREST_RATE = 0.1; // 10% APY
  const INIT_INTEREST_RATE_PER_SECOND = 0.1 / Base.YEAR_IN_SEC; // 10% APY

  for (const moduleInfo of Base.moneyMarketModuleList) {
    const moneyMarketModule = moduleInfo.moduleGenerator();
    context(`Money market: ${moduleInfo.name}`, () => {
      beforeEach(async () => {
        baseContracts = await Base.setupTest(accounts, moneyMarketModule);

        // Deploy ZeroCouponBond
        const zeroCouponBondTemplate = await ZeroCouponBond.new();
        const blockNow = await Base.latestBlockTimestamp();
        const zeroCouponBondAddress = await baseContracts.factory.predictAddress(
          zeroCouponBondTemplate.address,
          Base.DEFAULT_SALT
        );
        await baseContracts.stablecoin.approve(
          zeroCouponBondAddress,
          Base.num2str(Base.MinDepositAmount)
        );
        const zcbReceipt = await baseContracts.factory.createZeroCouponBond(
          zeroCouponBondTemplate.address,
          Base.DEFAULT_SALT,
          baseContracts.dInterestPool.address,
          baseContracts.vesting02.address,
          Base.num2str(blockNow + Base.YEAR_IN_SEC),
          Base.num2str(Base.MinDepositAmount),
          "88mph Zero Coupon Bond",
          "MPHZCB-Apr-2022",
          { from: acc0 }
        );
        zeroCouponBond = await Base.factoryReceiptToContract(
          zcbReceipt,
          ZeroCouponBond
        );
      });

      describe("mint", () => {
        context("happy path", () => {
          it("simple mint", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc1 mint ZCB
            await baseContracts.stablecoin.approve(
              zeroCouponBond.address,
              Base.INF,
              {
                from: acc1
              }
            );

            await zeroCouponBond.mint(Base.num2str(depositAmount), {
              from: acc1
            });
            // check mint amount
            const actualZCBMinted = await zeroCouponBond.balanceOf(acc1);
            const expectedZCBMinted = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              true
            ).plus(depositAmount);
            Base.assertEpsilonEq(
              actualZCBMinted,
              expectedZCBMinted,
              "minted ZCB amount incorrect"
            );
          });
        });

        context("edge cases", () => {
          it("should not mint higher amount than balance", async () => {
            const depositAmount = 10000 * Base.STABLECOIN_PRECISION;

            // acc1 mint ZCB
            await baseContracts.stablecoin.approve(
              zeroCouponBond.address,
              Base.INF,
              {
                from: acc1
              }
            );
            try {
              await zeroCouponBond.mint(Base.num2str(depositAmount), {
                from: acc1
              });
              assert.fail()
            } catch (error) {
              assertRevertMessage(error.message, "ERC20: transfer amount exceeds balance");
            }
          });
        });
      });

      describe("earlyRedeem", () => {
        context("happy path", () => {
          it("simple test", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc1 mint ZCB
            await baseContracts.stablecoin.approve(
              zeroCouponBond.address,
              Base.INF,
              {
                from: acc1
              }
            );
            await zeroCouponBond.mint(Base.num2str(depositAmount), {
              from: acc1
            });

            // acc1 redeems early
            const bondBalance = await zeroCouponBond.balanceOf(acc1);
            const beforeStablecoinBalance = await baseContracts.stablecoin.balanceOf(
              acc1
            );
            await zeroCouponBond.earlyRedeem(bondBalance, { from: acc1 });

            // check zcb balance
            const actualZCBBalance = await zeroCouponBond.balanceOf(acc1);
            const expectedZCBBalance = 0;
            Base.assertEpsilonEq(
              actualZCBBalance,
              expectedZCBBalance,
              "ZCB balance not 0 after early redeem"
            );

            // check stablecoin balance
            const actualRedeemedStablecoinAmount = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc1)
            ).minus(beforeStablecoinBalance);
            const expectedRedeemedStablecoinAmount = Base.applyEarlyWithdrawFee(
              depositAmount
            );
            Base.assertEpsilonEq(
              actualRedeemedStablecoinAmount,
              expectedRedeemedStablecoinAmount,
              "stablecoin not equal to deposit amount after early redeem"
            );
          });
        });

        context("edge cases", () => {
          it('should return an error if mature', async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc1 mint ZCB
            await baseContracts.stablecoin.approve(
              zeroCouponBond.address,
              Base.INF,
              {
                from: acc1
              }
            );
            await zeroCouponBond.mint(Base.num2str(depositAmount), {
              from: acc1
            });

            const bondBalance = await zeroCouponBond.balanceOf(acc1);
            
            await moneyMarketModule.timePass(1);

            try {
              await zeroCouponBond.earlyRedeem(bondBalance, { from: acc1 });
              assert.fail()
            } catch (error) {
              assertRevertMessage(error.message, "DInterest: mature")
            }
          })
        });
      });

      describe("withdrawDeposit", () => {
        context("happy path", () => {
          it("should withdraw deposit", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc1 mint ZCB
            await baseContracts.stablecoin.approve(
              zeroCouponBond.address,
              Base.INF,
              {
                from: acc1
              }
            );
            await zeroCouponBond.mint(Base.num2str(depositAmount), {
              from: acc1
            });

            // Wait 1 year
            await moneyMarketModule.timePass(1);

            await zeroCouponBond.withdrawDeposit({from: acc1});
            const dInterestBalanceAfterWithdrawal = await baseContracts.dInterestPool.totalDeposit();
            Base.assertEpsilonEq(
              dInterestBalanceAfterWithdrawal,
              0,
              "totalDeposit not updated after withdrawDeposit call"
            );
          })
        });

        context("edge cases", () => {
          it("should return 'ZeroCouponBond: already withdrawn' if balance equals 0", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc1 mint ZCB
            await baseContracts.stablecoin.approve(
              zeroCouponBond.address,
              Base.INF,
              {
                from: acc1
              }
            );
            await zeroCouponBond.mint(Base.num2str(depositAmount), {
              from: acc1
            });

            // Wait 1 year
            await moneyMarketModule.timePass(1);

            await zeroCouponBond.withdrawDeposit({from: acc1});
            try {
              await zeroCouponBond.withdrawDeposit({from: acc1});
              assert.fail();
            } catch (error) {
              assertRevertMessage(error.message, "ZeroCouponBond: already withdrawn");
            }
          })
        });
      });

      describe("redeem", () => {
        context("happy path", () => {
          it("simple test", async () => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc1 mint ZCB
            await baseContracts.stablecoin.approve(
              zeroCouponBond.address,
              Base.INF,
              {
                from: acc1
              }
            );
            await zeroCouponBond.mint(Base.num2str(depositAmount), {
              from: acc1
            });

            // Wait 1 year
            await moneyMarketModule.timePass(1);

            // acc1 redeems
            const bondBalance = await zeroCouponBond.balanceOf(acc1);
            const beforeStablecoinBalance = await baseContracts.stablecoin.balanceOf(
              acc1
            );
            await zeroCouponBond.redeem(bondBalance, true, { from: acc1 });

            // check zcb balance
            const actualZCBBalance = await zeroCouponBond.balanceOf(acc1);
            const expectedZCBBalance = 0;
            Base.assertEpsilonEq(
              actualZCBBalance,
              expectedZCBBalance,
              "ZCB balance not 0 after redeem"
            );

            // check stablecoin balance
            const actualRedeemedStablecoinAmount = BigNumber(
              await baseContracts.stablecoin.balanceOf(acc1)
            ).minus(beforeStablecoinBalance);
            const expectedRedeemedStablecoinAmount = Base.calcInterestAmount(
              depositAmount,
              INIT_INTEREST_RATE_PER_SECOND,
              Base.YEAR_IN_SEC,
              true
            ).plus(depositAmount);
            Base.assertEpsilonEq(
              actualRedeemedStablecoinAmount,
              expectedRedeemedStablecoinAmount,
              "stablecoin not equal to deposit amount plus interest amount after redeem"
            );
          });
        });

        context("edge cases", () => {
          it("use redeem for an earlyRedeem (before maturation): should return an error", async() => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc1 mint ZCB
            await baseContracts.stablecoin.approve(
              zeroCouponBond.address,
              Base.INF,
              {
                from: acc1
              }
            );
            await zeroCouponBond.mint(Base.num2str(depositAmount), {
              from: acc1
            });

            // Wait 2 months
            await moneyMarketModule.timePass(0.2);

            // acc1 redeems
            const bondBalance = await zeroCouponBond.balanceOf(acc1);
            try {
              await zeroCouponBond.redeem(bondBalance, true, { from: acc1 });
              assert.fail()
            } catch (error) {
              assertRevertMessage(error.message, "ZeroCouponBond: not mature")
            }
          });
          it("redeem with amount higher than balance: should return an error", async() => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc1 mint ZCB
            await baseContracts.stablecoin.approve(
              zeroCouponBond.address,
              Base.INF,
              {
                from: acc1
              }
            );
            await zeroCouponBond.mint(Base.num2str(depositAmount), {
              from: acc1
            });

            // Wait 1 year
            await moneyMarketModule.timePass(1);

            // acc1 redeems
            const bondBalance = await zeroCouponBond.balanceOf(acc1);
            try {
              await zeroCouponBond.redeem(bondBalance + 2, true, { from: acc1 });
              assert.fail()
            } catch (error) {
              assertRevertMessage(error.message, "ERC20: burn amount exceeds balance")
            }
          });
          it("redeem with withdrawDepositIfNeeded set to false but true needed: should return an error", async() => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc1 mint ZCB
            await baseContracts.stablecoin.approve(
              zeroCouponBond.address,
              Base.INF,
              {
                from: acc1
              }
            );
            await zeroCouponBond.mint(Base.num2str(depositAmount), {
              from: acc1
            });

            // Wait 1 year
            await moneyMarketModule.timePass(1);

            // acc1 redeems
            const bondBalance = await zeroCouponBond.balanceOf(acc1);
            try {
              await zeroCouponBond.redeem(bondBalance, false, { from: acc1 });
              assert.fail();
            } catch (error) {
              assertRevertMessage(error.message, "ERC20: transfer amount exceeds balance")
            }
          });
          it("redeem with withdrawDepositIfNeeded set to true but not needed: should not return an error", async() => {
            const depositAmount = 100 * Base.STABLECOIN_PRECISION;

            // acc1 mint ZCB
            await baseContracts.stablecoin.approve(
              zeroCouponBond.address,
              Base.INF,
              {
                from: acc1
              }
            );
            await zeroCouponBond.mint(Base.num2str(depositAmount), {
              from: acc1
            });

            // Wait 1 year
            await moneyMarketModule.timePass(1);
            
            await zeroCouponBond.withdrawDeposit(); 

            // acc1 redeems
            const bondBalance = await zeroCouponBond.balanceOf(acc1);
            const beforeStablecoinBalance = await baseContracts.stablecoin.balanceOf(
              acc1
            );

            await zeroCouponBond.redeem(bondBalance, true, { from: acc1 });
              // check zcb balance
              const actualZCBBalance = await zeroCouponBond.balanceOf(acc1);
              const expectedZCBBalance = 0;
              Base.assertEpsilonEq(
                actualZCBBalance,
                expectedZCBBalance,
                "ZCB balance not 0 after redeem"
              );
  
              // check stablecoin balance
              const actualRedeemedStablecoinAmount = BigNumber(
                await baseContracts.stablecoin.balanceOf(acc1)
              ).minus(beforeStablecoinBalance);
              const expectedRedeemedStablecoinAmount = Base.calcInterestAmount(
                depositAmount,
                INIT_INTEREST_RATE_PER_SECOND,
                Base.YEAR_IN_SEC,
                true
              ).plus(depositAmount);
              Base.assertEpsilonEq(
                actualRedeemedStablecoinAmount,
                expectedRedeemedStablecoinAmount,
                "stablecoin not equal to deposit amount plus interest amount after redeem"
              );
          })
        });
      });
    });
  }
});
