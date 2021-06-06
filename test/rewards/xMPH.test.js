const Base = require("../base");
const BigNumber = require("bignumber.js");
const { assert, artifacts } = require("hardhat");

const MPHToken = artifacts.require("MPHToken");
const xMPHArtifact = artifacts.require("xMPH");

contract("xMPH", accounts => {
  // Accounts
  const acc0 = accounts[0];
  const acc1 = accounts[1];
  const acc2 = accounts[2];

  // Contracts
  let mph, xMPH;

  // Constants
  const REWARD_UNLOCK_PERIOD = 14 * 24 * 60 * 60; // 14 days
  const depositAmount = 0.1 * Base.PRECISION;

  beforeEach(async () => {
    // deploy MPH
    mph = await MPHToken.new();
    await mph.initialize({ from: acc0 });

    // deploy xMPH
    xMPH = await xMPHArtifact.new();

    // mint MPH to test accounts and set approvals
    const mintAmount = Base.num2str(100 * Base.PRECISION);
    await mph.ownerMint(acc0, mintAmount, { from: acc0 });
    await mph.ownerMint(acc1, mintAmount, { from: acc0 });
    await mph.ownerMint(acc2, mintAmount, { from: acc0 });
    await mph.approve(xMPH.address, Base.INF, { from: acc0 });
    await mph.approve(xMPH.address, Base.INF, { from: acc1 });
    await mph.approve(xMPH.address, Base.INF, { from: acc2 });

    // initialize xMPH
    await xMPH.initialize(
      mph.address,
      Base.num2str(REWARD_UNLOCK_PERIOD),
      acc1,
      { from: acc0 }
    );
  });

  describe("deposit", () => {
    it("works", async () => {});

    it("sending MPH to xMPH contract and depositing should not change price per share", async () => {
      // send MPH to xMPH contract
      const transferAmount = Base.num2str(depositAmount);
      await mph.transfer(xMPH.address, transferAmount, { from: acc0 });

      // deposit MPH
      const beforePricePerShare = await xMPH.getPricePerFullShare();
      await xMPH.deposit(Base.num2str(depositAmount), { from: acc0 });
      const afterPricePerShare = await xMPH.getPricePerFullShare();

      // check if price per share is not changed
      Base.assertEpsilonEq(
        beforePricePerShare,
        afterPricePerShare,
        "price per share changed"
      );
    });
  });

  describe("withdraw", () => {
    it("works", async () => {});
  });

  describe("distributeReward", () => {
    it("works", async () => {});
  });
});
