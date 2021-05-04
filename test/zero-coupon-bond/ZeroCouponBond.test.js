const Base = require("../base");
const BigNumber = require("bignumber.js");
const { assert, artifacts } = require("hardhat");

const ZeroCouponBond = artifacts.require("ZeroCouponBond");

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

        context("edge cases", () => {});
      });

      describe("earlyRedeem", () => {
        context("happy path", () => {});

        context("edge cases", () => {});
      });

      describe("withdrawDeposit", () => {
        context("happy path", () => {});

        context("edge cases", () => {});
      });

      describe("redeem", () => {
        context("happy path", () => {});

        context("edge cases", () => {});
      });
    });
  }
});
