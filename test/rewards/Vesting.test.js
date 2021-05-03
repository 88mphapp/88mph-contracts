// Utilities

const { default: BigNumber } = require("bignumber.js");

// travel `time` seconds forward in time
function timeTravel(time) {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send(
      {
        jsonrpc: "2.0",
        method: "evm_increaseTime",
        params: [time],
        id: new Date().getTime()
      },
      (err, result) => {
        if (err) {
          return reject(err);
        }
        return resolve(result);
      }
    );
  });
}

async function latestBlockTimestamp() {
  return (await web3.eth.getBlock("latest")).timestamp;
}

// Converts a JS number into a string that doesn't use scientific notation
function num2str(num) {
  return BigNumber(num)
    .integerValue()
    .toFixed();
}

contract("Vesting", accounts => {
  // Accounts
  const acc0 = accounts[0];
  const acc1 = accounts[1];
  const acc2 = accounts[2];

  // Constants
  const TOKEN_PRECISION = 1e6;
  const DAY = 24 * 60 * 60;

  // Contracts
  let token, vesting;

  beforeEach(async () => {
    const ERC20Mock = artifacts.require("ERC20Mock");
    token = await ERC20Mock.new();
    // Mint token
    const mintAmount = 1000 * TOKEN_PRECISION;
    await token.mint(acc0, num2str(mintAmount));
    await token.mint(acc1, num2str(mintAmount));
    await token.mint(acc2, num2str(mintAmount));

    const Vesting = artifacts.require("Vesting");
    vesting = await Vesting.new(token.address);
  });

  it("should vest full amount after vesting period", async () => {
    // acc0 vest 10 tokens to acc1 for 7 days
    const vestAmount = 10 * TOKEN_PRECISION;
    const vestPeriod = 7 * DAY;
    await token.approve(vesting.address, num2str(vestAmount), { from: acc0 });
    await vesting.vest(acc1, num2str(vestAmount), num2str(vestPeriod), {
      from: acc0
    });

    // wait 10 days
    await timeTravel(10 * DAY);

    // acc1 withdraws vested amount
    const acc1BeforeBalance = BigNumber(await token.balanceOf(acc1));
    await vesting.withdrawVested(acc1, 0, { from: acc0 });

    // verify amount
    const receivedAmount = BigNumber(await token.balanceOf(acc1)).minus(
      acc1BeforeBalance
    );
    const expectedReceiveAmount = BigNumber(vestAmount);
    assert(
      receivedAmount.eq(expectedReceiveAmount),
      "fully vested amount incorrect"
    );
  });

  it("should vest linear partial amount during vesting period", async () => {
    // acc0 vest 10 tokens to acc1 for 7 days
    const vestAmount = 10 * TOKEN_PRECISION;
    const vestPeriod = 7 * DAY;
    await token.approve(vesting.address, num2str(vestAmount), { from: acc0 });
    await vesting.vest(acc1, num2str(vestAmount), num2str(vestPeriod), {
      from: acc0
    });

    // wait 3 days
    await timeTravel(3 * DAY);

    // acc1 withdraws partially vested amount
    const acc1BeforeBalance = BigNumber(await token.balanceOf(acc1));
    await vesting.withdrawVested(acc1, 0, { from: acc0 });

    // verify amount
    const receivedAmount = BigNumber(await token.balanceOf(acc1)).minus(
      acc1BeforeBalance
    );
    const expectedReceiveAmount = BigNumber(vestAmount)
      .times(3 * DAY)
      .div(7 * DAY)
      .integerValue();
    assert(
      receivedAmount.eq(expectedReceiveAmount),
      "partially vested amount incorrect"
    );
  });

  it("should vest full amount after vesting period only once", async () => {
    // acc0 vest 10 tokens to acc1 for 7 days
    const vestAmount = 10 * TOKEN_PRECISION;
    const vestPeriod = 7 * DAY;
    await token.approve(vesting.address, num2str(vestAmount), { from: acc0 });
    await vesting.vest(acc1, num2str(vestAmount), num2str(vestPeriod), {
      from: acc0
    });

    // wait 10 days
    await timeTravel(10 * DAY);

    // acc1 withdraws vested amount
    const acc1BeforeBalance = BigNumber(await token.balanceOf(acc1));
    await vesting.withdrawVested(acc1, 0, { from: acc0 });

    // acc1 withdraws many times
    const withdrawNum = 10;
    for (let i = 0; i < withdrawNum; i++) {
      await timeTravel(1 * DAY);
      await vesting.withdrawVested(acc1, 0, { from: acc0 });
    }

    // verify amount
    const receivedAmount = BigNumber(await token.balanceOf(acc1)).minus(
      acc1BeforeBalance
    );
    const expectedReceiveAmount = BigNumber(vestAmount);
    assert(
      receivedAmount.eq(expectedReceiveAmount),
      "fully vested amount incorrect"
    );
  });

  it("should vest linear partial amount during vesting period only once", async () => {
    // acc0 vest 10 tokens to acc1 for 7 days
    const vestAmount = 10 * TOKEN_PRECISION;
    const vestPeriod = 7 * DAY;
    await token.approve(vesting.address, num2str(vestAmount), { from: acc0 });
    const vestTimestamp = await latestBlockTimestamp();
    await vesting.vest(acc1, num2str(vestAmount), num2str(vestPeriod), {
      from: acc0
    });

    // wait 3 days
    await timeTravel(3 * DAY);

    // acc1 withdraws partially vested amount
    const acc1BeforeBalance = BigNumber(await token.balanceOf(acc1));
    await vesting.withdrawVested(acc1, 0, { from: acc0 });

    // acc1 withdraws many times
    const withdrawNum = 10;
    for (let i = 0; i < withdrawNum; i++) {
      await vesting.withdrawVested(acc1, 0, { from: acc0 });
    }

    // verify amount
    const actualTimePassed = BigNumber(
      (await latestBlockTimestamp()) - 1
    ).minus(vestTimestamp);
    const receivedAmount = BigNumber(await token.balanceOf(acc1)).minus(
      acc1BeforeBalance
    );
    const expectedReceiveAmount = BigNumber(vestAmount)
      .times(actualTimePassed)
      .div(7 * DAY)
      .integerValue();
    assert(
      receivedAmount.lte(expectedReceiveAmount),
      "partially vested amount incorrect"
    );
  });

  it("should fail tx when withdrawing from non-existent vest object", async () => {
    // acc0 vest 10 tokens to acc1 for 7 days
    const vestAmount = 10 * TOKEN_PRECISION;
    const vestPeriod = 7 * DAY;
    await token.approve(vesting.address, num2str(vestAmount), { from: acc0 });
    await vesting.vest(acc1, num2str(vestAmount), num2str(vestPeriod), {
      from: acc0
    });

    // wait 7 days
    await timeTravel(7 * DAY);

    // acc1 withdraws non-existent vest, should fail transaction
    try {
      await vesting.withdrawVested(acc1, 1, { from: acc0 });
      assert.fail("withdrew from non-existent vest");
    } catch {}
  });
});
