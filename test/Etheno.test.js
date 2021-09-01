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

  const moduleInfo = Base.moneyMarketModuleList[0];
  const moneyMarketModule = moduleInfo.moduleGenerator();
  context(`Money market: ${moduleInfo.name}`, () => {
    beforeEach(async () => {
      baseContracts = await Base.setupTest(accounts, moneyMarketModule);
      // print out mapping from contract names to addresses
      for (const c of Object.values(baseContracts)) {
        if (c.constructor._json != null) {
          console.log(c.constructor._json.contractName + " " + c.address);
        }
      }
    });

    describe("empty", () => {
      it("nothin here", () => {});
    });
  });
});
