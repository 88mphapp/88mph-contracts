const env = require("@nomiclabs/buidler");
const BigNumber = require("bignumber.js");

async function main() {
  const FeeModel = env.artifacts.require("FeeModel");
  const feeModel = await FeeModel.new();
  console.log(`Deployed FeeModel at address ${feeModel.address}`);

  const CompoundERC20Market = env.artifacts.require("CompoundERC20Market");
  const cTokenAddress = "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643"; // cDAI Mainnet
  const comptrollerAddress = "0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b"; // Comptroller Mainnet
  const compAddress = "0xc00e94cb662c3520282e6f5717214004a7f26888"; // COMP Mainnet
  const stablecoinAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F"; // DAI Mainnet
  const market = await CompoundERC20Market.new(cTokenAddress, comptrollerAddress, compAddress, feeModel.address, stablecoinAddress);
  console.log(`Deployed CompoundERC20Market at address ${market.address}`);

  const NFT = env.artifacts.require("NFT");
  const depositNFT = await NFT.new("88mph Compound-Pool Deposit", "88mph-Compound-Deposit");
  console.log(`Deployed depositNFT at address ${depositNFT.address}`);
  const fundingNFT = await NFT.new("88mph Compound-Pool Long Position", "88mph-Compound-Long");
  console.log(`Deployed fundingNFT at address ${fundingNFT.address}`);

  const DInterest = env.artifacts.require("DInterest");
  const UIRMultiplier = BigNumber(0.75 * 1e18).integerValue().toFixed(); // Minimum safe avg interest rate multiplier
  const MinDepositPeriod = 90 * 24 * 60 * 60; // 90 days in seconds
  const MaxDepositAmount = BigNumber(10000 * 1e18).toFixed(); // 10000 stablecoins
  const dInterestPool = await DInterest.new(UIRMultiplier, MinDepositPeriod, MaxDepositAmount, market.address, stablecoinAddress, feeModel.address, depositNFT.address, fundingNFT.address);
  console.log(`Deployed DInterest at address ${dInterestPool.address}`);

  await market.transferOwnership(dInterestPool.address);
  console.log(`Transferred AaveMarket's ownership to ${dInterestPool.address}`);

  await depositNFT.transferOwnership(dInterestPool.address);
  console.log(`Transferred depositNFT's ownership to ${dInterestPool.address}`);

  await fundingNFT.transferOwnership(dInterestPool.address);
  console.log(`Transferred fundingNFT's ownership to ${dInterestPool.address}`);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
