// Libraries
const BigNumber = require("bignumber.js");

// Contract artifacts
const DInterest = artifacts.require("DInterest");
const AaveMarket = artifacts.require("AaveMarket");
const CompoundERC20Market = artifacts.require("CompoundERC20Market");
const CERC20Mock = artifacts.require("CERC20Mock");
const ERC20Mock = artifacts.require("ERC20Mock");

// Utilities
// travel `time` seconds forward in time
function timeTravel(time) {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send({
      jsonrpc: "2.0",
      method: "evm_increaseTime",
      params: [time],
      id: new Date().getTime()
    }, (err, result) => {
      if (err)
        return reject(err);
      return resolve(result)
    });
  });
}

async function latestBlockTimestamp() {
  return (await web3.eth.getBlock("latest")).timestamp;
}

// Converts a JS number into a string that doesn't use scientific notation
function num2str(num) {
  return BigNumber(num).integerValue().toFixed();
}

// Constants
const UIRMultiplier = BigNumber(0.5 * 1e18).integerValue().toFixed(); // Offered interest rate is multiplied by 0.5
const MinDepositPeriod = 90 * 24 * 60 * 60; // 90 days in seconds
const PRECISION = 1e18;
const YEAR_IN_BLOCKS = 2104400; // Number of blocks in a year
const YEAR_IN_SEC = 31556952; // Number of seconds in a year

// Tests
contract("DInterest: Compound", accounts => {
  // Accounts
  let acc0 = accounts[0];
  let acc1 = accounts[1];

  // Contract instances
  let stablecoin;
  let cToken;
  let dInterestPool;
  let market;

  // Constants
  const INIT_EXRATE = 2e26; // 1 cToken = 0.02 stablecoin
  const INIT_INTEREST_RATE = 0.1; // 10% APY

  beforeEach(async function () {
    // Initialize mock stablecoin and cToken
    stablecoin = await ERC20Mock.new();
    cToken = await CERC20Mock.new(stablecoin.address);

    // Mint stablecoin
    const mintAmount = 1000 * PRECISION;
    await stablecoin.mint(cToken.address, num2str(mintAmount));
    await stablecoin.mint(acc0, num2str(mintAmount));
    await stablecoin.mint(acc1, num2str(mintAmount));

    // Initialize the money market
    market = await CompoundERC20Market.new(cToken.address, stablecoin.address);

    // Initialize the DInterest pool
    dInterestPool = await DInterest.new(UIRMultiplier, MinDepositPeriod, market.address, stablecoin.address);

    // Transfer the ownership of the money market to the DInterest pool
    await market.transferOwnership(dInterestPool.address);
  });

  it("deposit()", async function () {
    const depositAmount = 10 * PRECISION;

    // acc0 deposits stablecoin into the DInterest pool for 1 year
    await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 });
    let blockNow = await latestBlockTimestamp();
    await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc0 });

    // Verify state changes TODO
    // Verify upfront interest amount
    // Verify totalDeposit
    const totalDeposit0 = BigNumber(await dInterestPool.totalDeposit());
    assert(totalDeposit0.eq(depositAmount), "totalDeposit not updated after acc0 deposited");
  });

  it("withdraw()", async function () {
    const depositAmount = 10 * PRECISION;

    // acc0 deposits stablecoin into the DInterest pool for 1 year
    await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc0 });
    let blockNow = await latestBlockTimestamp();
    await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc0 });

    // Wait 6 months
    await timeTravel(0.5 * YEAR_IN_SEC);

    // acc1 deposits stablecoin into the DInterest pool for 1 year
    await stablecoin.approve(dInterestPool.address, num2str(depositAmount), { from: acc1 });
    blockNow = await latestBlockTimestamp();
    await dInterestPool.deposit(num2str(depositAmount), blockNow + YEAR_IN_SEC, { from: acc1 });

    // Wait 6 months
    await timeTravel(0.5 * YEAR_IN_SEC);

    // Raise cToken exchange rate
    let rateAfter1y = INIT_EXRATE * (1 + INIT_INTEREST_RATE);
    await cToken._setExchangeRateStored(num2str(rateAfter1y));

    // acc0 withdraws
    const acc0BeforeBalance = await stablecoin.balanceOf(acc0);
    await dInterestPool.withdraw(0, { from: acc0 });

    // Verify withdrawn amount
    const acc0CurrentBalance = await stablecoin.balanceOf(acc0);
    assert.equal(acc0CurrentBalance - acc0BeforeBalance, depositAmount, "acc0 didn't withdraw correct amount of stablecoin");
    // Verify totalDeposit
    const totalDeposit0 = BigNumber(await dInterestPool.totalDeposit());
    assert(totalDeposit0.eq(depositAmount), "totalDeposit not updated after acc0 withdrawed");
  
    // Wait 6 months
    await timeTravel(0.5 * YEAR_IN_SEC);

    // Raise cToken exchange rate
    let rateAfter1y6m = INIT_EXRATE * (1 + 1.5 * INIT_INTEREST_RATE);
    await cToken._setExchangeRateStored(num2str(rateAfter1y6m));

    // acc1 withdraws
    const acc1BeforeBalance = await stablecoin.balanceOf(acc1);
    await dInterestPool.withdraw(0, { from: acc1 });

    // Verify withdrawn amount
    const acc1CurrentBalance = await stablecoin.balanceOf(acc1);
    assert.equal(acc1CurrentBalance - acc1BeforeBalance, depositAmount, "acc1 didn't withdraw correct amount of stablecoin");
    // Verify totalDeposit
    const totalDeposit1 = BigNumber(await dInterestPool.totalDeposit());
    assert(totalDeposit1.eq(0), "totalDeposit not updated after acc1 withdrawed");
  });
});