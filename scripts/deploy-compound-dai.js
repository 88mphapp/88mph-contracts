const env = require("@nomiclabs/buidler");
const BigNumber = require("bignumber.js");

async function main() {
  await env.run("compile");

  const CompoundERC20Market = env.artifacts.require("CompoundERC20Market");
  const cTokenAddress = "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643"; // cDAI Mainnet
  const stablecoinAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F"; // DAI Mainnet
  const market = await CompoundERC20Market.new(cTokenAddress, stablecoinAddress);
  console.log(`Deployed CompoundERC20Market at address ${market.address}`);

  const FeeModel = env.artifacts.require("FeeModel");
  const feeModel = await FeeModel.new();
  console.log(`Deployed FeeModel at address ${feeModel.address}`);

  const DInterest = env.artifacts.require("DInterest");
  const UIRMultiplier = BigNumber(0.5 * 1e18).integerValue().toFixed(); // Minimum safe avg interest rate multiplier
  const MinDepositPeriod = 90 * 24 * 60 * 60; // 90 days in seconds
  const dInterestPool = await DInterest.new(UIRMultiplier, MinDepositPeriod, market.address, stablecoinAddress, feeModel.address);
  console.log(`Deployed DInterest at address ${dInterestPool.address}`);

  await market.transferOwnership(dInterestPool.address);
  console.log(`Transferred CompoundERC20Market's ownership to ${dInterestPool.address}`);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
