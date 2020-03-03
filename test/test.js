const DInterest = artifacts.require("DInterest");

contract("DInterest", accounts => {
  let dInterestPool;

  beforeEach(async function () {
    dInterestPool = await DInterest.new();
  });

  it("", async function() {
    
  });
});