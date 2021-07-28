// Libraries
const BigNumber = require("bignumber.js");
const { assert, artifacts } = require("hardhat");

// Contract artifacts
const DInterest = (module.exports.DInterest = artifacts.require("DInterest"));
const DInterestLens = (module.exports.DInterest = artifacts.require(
  "DInterestLens"
));
const PercentageFeeModel = (module.exports.PercentageFeeModel = artifacts.require(
  "PercentageFeeModel"
));
const LinearDecayInterestModel = (module.exports.LinearDecayInterestModel = artifacts.require(
  "LinearDecayInterestModel"
));
const NFT = (module.exports.NFT = artifacts.require("NFT"));
const FundingMultitoken = (module.exports.FundingMultitoken = artifacts.require(
  "FundingMultitoken"
));
const Factory = (module.exports.Factory = artifacts.require("Factory"));
const MPHToken = (module.exports.MPHToken = artifacts.require("MPHToken"));
const MPHMinter = (module.exports.MPHMinter = artifacts.require("MPHMinter"));
const ERC20Mock = (module.exports.ERC20Mock = artifacts.require("ERC20Mock"));
const EMAOracle = (module.exports.EMAOracle = artifacts.require("EMAOracle"));
const Vesting02 = (module.exports.Vesting02 = artifacts.require("Vesting02"));
const ERC20Wrapper = (module.exports.ERC20Wrapper = artifacts.require(
  "ERC20Wrapper"
));

// Constants
const PRECISION = (module.exports.PRECISION = 1e18);
const STABLECOIN_PRECISION = (module.exports.STABLECOIN_PRECISION = 1e6);
const STABLECOIN_DECIMALS = (module.exports.STABLECOIN_DECIMALS = 6);
const YEAR_IN_SEC = (module.exports.YEAR_IN_SEC = 31556952); // Number of seconds in a year
const multiplierIntercept = (module.exports.multiplierIntercept =
  0.5 * PRECISION);
const multiplierSlope = (module.exports.multiplierSlope =
  (0.25 / YEAR_IN_SEC) * PRECISION);
const MaxDepositPeriod = (module.exports.MaxDepositPeriod = 3 * YEAR_IN_SEC); // 3 years in seconds
const MinDepositAmount = (module.exports.MinDepositAmount = BigNumber(
  0.1 * STABLECOIN_PRECISION
).toFixed()); // 0.1 stablecoin
const PoolDepositorRewardMintMultiplier = (module.exports.PoolDepositorRewardMintMultiplier = BigNumber(
  3.168873e-13 * PRECISION * (PRECISION / STABLECOIN_PRECISION)
).toFixed()); // 1e5 stablecoin * 1 year => 1 MPH
const PoolFunderRewardMultiplier = (module.exports.PoolFunderRewardMultiplier = BigNumber(
  1e-13 * PRECISION * (PRECISION / STABLECOIN_PRECISION)
).toFixed()); // 1e5 stablecoin => 1 MPH
const DevRewardMultiplier = (module.exports.DevRewardMultiplier = BigNumber(
  0.1 * PRECISION
).toFixed());
const GovRewardMultiplier = (module.exports.GovRewardMultiplier = BigNumber(
  0.1 * PRECISION
).toFixed());
const EMAUpdateInterval = (module.exports.EMAUpdateInterval = 24 * 60 * 60);
const EMASmoothingFactor = (module.exports.EMASmoothingFactor = BigNumber(
  2 * PRECISION
).toFixed());
const EMAAverageWindowInIntervals = (module.exports.EMAAverageWindowInIntervals = 30);
const interestFee = (module.exports.interestFee = BigNumber(
  0.2 * PRECISION
).toFixed());
const earlyWithdrawFee = (module.exports.earlyWithdrawFee = BigNumber(
  0.005 * PRECISION
).toFixed());
const MINTER_BURNER_ROLE = (module.exports.MINTER_BURNER_ROLE = web3.utils.soliditySha3(
  "MINTER_BURNER_ROLE"
));
const DIVIDEND_ROLE = (module.exports.DIVIDEND_ROLE = web3.utils.soliditySha3(
  "DIVIDEND_ROLE"
));
const WHITELISTER_ROLE = (module.exports.WHITELISTER_ROLE = web3.utils.soliditySha3(
  "WHITELISTER_ROLE"
));
const WHITELISTED_POOL_ROLE = (module.exports.WHITELISTED_POOL_ROLE = web3.utils.soliditySha3(
  "WHITELISTED_POOL_ROLE"
));

const epsilon = (module.exports.epsilon = 1e-4);
const INF = (module.exports.INF = BigNumber(2)
  .pow(256)
  .minus(1)
  .toFixed());
const ZERO_ADDR = (module.exports.ZERO_ADDR =
  "0x0000000000000000000000000000000000000000");
const DEFAULT_SALT = (module.exports.DEFAULT_SALT =
  "0x0000000000000000000000000000000000000000000000000000000000000000");

// Utilities
// travel `time` seconds forward in time
const timeTravel = (module.exports.timeTravel = time => {
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
});

const latestBlockTimestamp = (module.exports.latestBlockTimestamp = async () => {
  return (await web3.eth.getBlock("latest")).timestamp;
});

const calcFeeAmount = (module.exports.calcFeeAmount = interestAmount => {
  interestAmount = BigNumber(interestAmount);
  return interestAmount.times(interestFee).div(PRECISION);
});

const applyFee = (module.exports.applyFee = interestAmount => {
  interestAmount = BigNumber(interestAmount);
  return interestAmount.minus(calcFeeAmount(interestAmount));
});

const applyEarlyWithdrawFee = (module.exports.applyEarlyWithdrawFee = depositAmount => {
  depositAmount = BigNumber(depositAmount);
  return depositAmount.minus(
    depositAmount.times(earlyWithdrawFee).div(PRECISION)
  );
});

const getIRMultiplier = (module.exports.getIRMultiplier = depositPeriodInSeconds => {
  const multiplierDecrease = BigNumber(depositPeriodInSeconds).times(
    multiplierSlope
  );
  if (multiplierDecrease.gte(multiplierIntercept)) {
    return 0;
  } else {
    return BigNumber(multiplierIntercept)
      .minus(multiplierDecrease)
      .div(PRECISION)
      .toNumber();
  }
});

const calcInterestAmount = (module.exports.calcInterestAmount = (
  depositAmount,
  interestRatePerSecond,
  depositPeriodInSeconds,
  applyFee
) => {
  const IRMultiplier = getIRMultiplier(depositPeriodInSeconds);
  const interestBeforeFee = BigNumber(depositAmount)
    .times(depositPeriodInSeconds)
    .times(interestRatePerSecond)
    .times(IRMultiplier);
  return applyFee
    ? interestBeforeFee.minus(calcFeeAmount(interestBeforeFee))
    : interestBeforeFee;
});

// Converts a JS number into a string that doesn't use scientific notation
const num2str = (module.exports.num2str = num => {
  return BigNumber(num)
    .integerValue()
    .toFixed();
});

const epsilonEq = (module.exports.epsilonEq = (curr, prev, ep) => {
  const _epsilon = ep || epsilon;
  return (
    BigNumber(curr).eq(prev) ||
    (!BigNumber(prev).isZero() &&
      BigNumber(curr)
        .minus(prev)
        .div(prev)
        .abs()
        .lt(_epsilon)) ||
    (!BigNumber(curr).isZero() &&
      BigNumber(prev)
        .minus(curr)
        .div(curr)
        .abs()
        .lt(_epsilon))
  );
});

const assertEpsilonEq = (module.exports.assertEpsilonEq = (a, b, message) => {
  assert(
    epsilonEq(a, b),
    `assertEpsilonEq error, a=${BigNumber(a).toString()}, b=${BigNumber(
      b
    ).toString()}, message=${message}`
  );
});

const factoryReceiptToContract = (module.exports.factoryReceiptToContract = async (
  receipt,
  contractArtifact
) => {
  return await contractArtifact.at(
    receipt.logs[receipt.logs.length - 1].args.clone
  );
});

const aaveMoneyMarketModule = () => {
  // Contract artifacts
  const AaveMarket = artifacts.require("AaveMarket");
  const ATokenMock = artifacts.require("ATokenMock");
  const LendingPoolMock = artifacts.require("LendingPoolMock");
  const LendingPoolAddressesProviderMock = artifacts.require(
    "LendingPoolAddressesProviderMock"
  );
  const AaveMiningMock = artifacts.require("AaveMiningMock");
  const ERC20Mock = artifacts.require("ERC20Mock");

  let aToken;
  let lendingPool;
  let lendingPoolAddressesProvider;
  let aaveMining;
  let aave;
  const aTokenAddresssList = [];

  const deployMoneyMarket = async (accounts, factory, stablecoin, rewards) => {
    // Initialize mock Aave contracts
    aToken = await ATokenMock.new(stablecoin.address);
    if (!aTokenAddresssList.includes(aToken.address)) {
      aTokenAddresssList.push(aToken.address);
    }
    lendingPool = await LendingPoolMock.new();
    await lendingPool.setReserveAToken(stablecoin.address, aToken.address);
    lendingPoolAddressesProvider = await LendingPoolAddressesProviderMock.new();
    await lendingPoolAddressesProvider.setLendingPoolImpl(lendingPool.address);
    aave = await ERC20Mock.new();
    aaveMining = await AaveMiningMock.new(aave.address);

    // Mint stablecoins
    const mintAmount = 1000 * STABLECOIN_PRECISION;
    await stablecoin.mint(lendingPool.address, num2str(mintAmount));

    // Initialize the money market
    const marketTemplate = await AaveMarket.new();
    const marketReceipt = await factory.createAaveMarket(
      marketTemplate.address,
      DEFAULT_SALT,
      lendingPoolAddressesProvider.address,
      aToken.address,
      aaveMining.address,
      rewards,
      accounts[0],
      stablecoin.address
    );
    return await factoryReceiptToContract(marketReceipt, AaveMarket);
  };

  const timePass = async timeInYears => {
    await timeTravel(timeInYears * YEAR_IN_SEC);
    for (const aTokenAddress of aTokenAddresssList) {
      const aToken = await ATokenMock.at(aTokenAddress);
      await aToken.mintInterest(num2str(timeInYears * YEAR_IN_SEC));
    }
  };

  return {
    deployMoneyMarket,
    timePass
  };
};

const bProtocolMoneyMarketModule = () => {
  // Contract artifacts
  const BProtocolMarket = artifacts.require("BProtocolMarket");
  const CERC20Mock = artifacts.require("CERC20Mock");
  const RegistryMock = artifacts.require("RegistryMock");
  const BComptrollerMock = artifacts.require("BComptrollerMock");

  let bComptroller;
  let cToken;
  let comp;
  let registry;
  const cTokenAddressList = [];

  const INIT_INTEREST_RATE = 0.1; // 10% APY

  const deployMoneyMarket = async (accounts, factory, stablecoin, rewards) => {
    // Deploy B.Protocol mock contracts
    cToken = await CERC20Mock.new(stablecoin.address);
    if (!cTokenAddressList.includes(cToken.address)) {
      cTokenAddressList.push(cToken.address);
    }
    comp = await ERC20Mock.new();
    registry = await RegistryMock.new(comp.address);
    bComptroller = await BComptrollerMock.new(registry.address);

    // Mint stablecoins
    const mintAmount = 1000 * STABLECOIN_PRECISION;
    await stablecoin.mint(cToken.address, num2str(mintAmount));

    // Initialize the money market
    const marketTemplate = await BProtocolMarket.new();
    const marketReceipt = await factory.createBProtocolMarket(
      marketTemplate.address,
      DEFAULT_SALT,
      cToken.address,
      bComptroller.address,
      rewards,
      accounts[0],
      stablecoin.address
    );
    return await factoryReceiptToContract(marketReceipt, BProtocolMarket);
  };

  const timePass = async timeInYears => {
    await timeTravel(timeInYears * YEAR_IN_SEC);
    for (const cTokenAddress of cTokenAddressList) {
      const cToken = await CERC20Mock.at(cTokenAddress);
      const currentExRate = BigNumber(await cToken.exchangeRateStored());
      const rateAfterTimePasses = BigNumber(currentExRate).times(
        1 + timeInYears * INIT_INTEREST_RATE
      );
      await cToken._setExchangeRateStored(num2str(rateAfterTimePasses));
    }
  };

  return {
    deployMoneyMarket,
    timePass
  };
};

const compoundERC20MoneyMarketModule = () => {
  // Contract artifacts
  const CompoundERC20Market = artifacts.require("CompoundERC20Market");
  const CERC20Mock = artifacts.require("CERC20Mock");
  const ComptrollerMock = artifacts.require("ComptrollerMock");

  let cToken;
  let comptroller;
  let comp;
  const cTokenAddressList = [];

  const INIT_INTEREST_RATE = 0.1; // 10% APY

  const deployMoneyMarket = async (accounts, factory, stablecoin, rewards) => {
    // Deploy Compound mock contracts
    cToken = await CERC20Mock.new(stablecoin.address);
    if (!cTokenAddressList.includes(cToken.address)) {
      cTokenAddressList.push(cToken.address);
    }
    comp = await ERC20Mock.new();
    comptroller = await ComptrollerMock.new(comp.address);

    // Mint stablecoins
    const mintAmount = 1000 * STABLECOIN_PRECISION;
    await stablecoin.mint(cToken.address, num2str(mintAmount));

    // Initialize the money market
    const marketTemplate = await CompoundERC20Market.new();
    const marketReceipt = await factory.createCompoundERC20Market(
      marketTemplate.address,
      DEFAULT_SALT,
      cToken.address,
      comptroller.address,
      rewards,
      accounts[0],
      stablecoin.address
    );
    return await factoryReceiptToContract(marketReceipt, CompoundERC20Market);
  };

  const timePass = async timeInYears => {
    await timeTravel(timeInYears * YEAR_IN_SEC);
    for (const cTokenAddress of cTokenAddressList) {
      const cToken = await CERC20Mock.at(cTokenAddress);
      const currentExRate = BigNumber(await cToken.exchangeRateStored());
      const rateAfterTimePasses = BigNumber(currentExRate).times(
        1 + timeInYears * INIT_INTEREST_RATE
      );
      await cToken._setExchangeRateStored(num2str(rateAfterTimePasses));
    }
  };

  return {
    deployMoneyMarket,
    timePass
  };
};

const creamERC20MoneyMarketModule = () => {
  // Contract artifacts
  const CreamERC20Market = artifacts.require("CreamERC20Market");
  const CERC20Mock = artifacts.require("CERC20Mock");

  let cToken;
  const cTokenAddressList = [];
  const INIT_INTEREST_RATE = 0.1; // 10% APY

  const deployMoneyMarket = async (accounts, factory, stablecoin, rewards) => {
    // Deploy Compound mock contracts
    cToken = await CERC20Mock.new(stablecoin.address);
    if (!cTokenAddressList.includes(cToken.address)) {
      cTokenAddressList.push(cToken.address);
    }

    // Mint stablecoins
    const mintAmount = 1000 * STABLECOIN_PRECISION;
    await stablecoin.mint(cToken.address, num2str(mintAmount));

    // Initialize the money market
    const marketTemplate = await CreamERC20Market.new();
    const marketReceipt = await factory.createCreamERC20Market(
      marketTemplate.address,
      DEFAULT_SALT,
      cToken.address,
      accounts[0],
      stablecoin.address
    );
    return await factoryReceiptToContract(marketReceipt, CreamERC20Market);
  };

  const timePass = async timeInYears => {
    await timeTravel(timeInYears * YEAR_IN_SEC);
    for (const cTokenAddress of cTokenAddressList) {
      const cToken = await CERC20Mock.at(cTokenAddress);
      const currentExRate = BigNumber(await cToken.exchangeRateStored());
      const rateAfterTimePasses = BigNumber(currentExRate).times(
        1 + timeInYears * INIT_INTEREST_RATE
      );
      await cToken._setExchangeRateStored(num2str(rateAfterTimePasses));
    }
  };

  return {
    deployMoneyMarket,
    timePass
  };
};

const harvestMoneyMarketModule = () => {
  // Contract artifacts
  const VaultMock = artifacts.require("VaultMock");
  const HarvestStakingMock = artifacts.require("HarvestStakingMock");
  const HarvestMarket = artifacts.require("HarvestMarket");

  let vault;
  let stablecoin;
  const vaultAddressList = [];
  const INIT_INTEREST_RATE = 0.1; // 10% APY

  const deployMoneyMarket = async (accounts, factory, _stablecoin, rewards) => {
    // Deploy mock contracts
    stablecoin = _stablecoin;
    vault = await VaultMock.new(stablecoin.address);
    if (!vaultAddressList.includes(vault.address)) {
      vaultAddressList.push(vault.address);
    }

    // Initialize FARM rewards
    const farmToken = await ERC20Mock.new();
    const farmRewards = 1000 * STABLECOIN_PRECISION;
    const harvestStaking = await HarvestStakingMock.new(
      vault.address,
      farmToken.address,
      Math.floor(Date.now() / 1e3 - 60)
    );
    await farmToken.mint(harvestStaking.address, num2str(farmRewards));
    await harvestStaking.setRewardDistribution(accounts[0], true);
    await harvestStaking.notifyRewardAmount(num2str(farmRewards), {
      from: accounts[0]
    });

    // Initialize the money market
    const marketTemplate = await HarvestMarket.new();
    const marketReceipt = await factory.createHarvestMarket(
      marketTemplate.address,
      DEFAULT_SALT,
      vault.address,
      rewards,
      harvestStaking.address,
      accounts[0],
      stablecoin.address
    );
    return await factoryReceiptToContract(marketReceipt, HarvestMarket);
  };

  const timePass = async timeInYears => {
    await timeTravel(timeInYears * YEAR_IN_SEC);
    for (const vaultAddress of vaultAddressList) {
      const vault = await VaultMock.at(vaultAddress);
      const mintAmount = BigNumber(await stablecoin.balanceOf(vault.address))
        .times(INIT_INTEREST_RATE)
        .times(timeInYears);
      if (mintAmount.gt(0)) {
        await stablecoin.mint(vault.address, num2str(mintAmount));
      }
    }
  };

  return {
    deployMoneyMarket,
    timePass
  };
};

const yvaultMoneyMarketModule = () => {
  // Contract artifacts
  const VaultMock = artifacts.require("VaultMock");
  const YVaultMarket = artifacts.require("YVaultMarket");

  let vault;
  let stablecoin;
  const vaultAddressList = [];
  const INIT_INTEREST_RATE = 0.1; // 10% APY

  const deployMoneyMarket = async (accounts, factory, _stablecoin, rewards) => {
    // Deploy mock contracts
    stablecoin = _stablecoin;
    vault = await VaultMock.new(stablecoin.address);
    if (!vaultAddressList.includes(vault.address)) {
      vaultAddressList.push(vault.address);
    }

    // Initialize the money market
    const marketTemplate = await YVaultMarket.new();
    const marketReceipt = await factory.createYVaultMarket(
      marketTemplate.address,
      DEFAULT_SALT,
      vault.address,
      accounts[0],
      stablecoin.address
    );
    return await factoryReceiptToContract(marketReceipt, YVaultMarket);
  };

  const timePass = async timeInYears => {
    await timeTravel(timeInYears * YEAR_IN_SEC);
    for (const vaultAddress of vaultAddressList) {
      const vault = await VaultMock.at(vaultAddress);
      const mintAmount = BigNumber(await stablecoin.balanceOf(vault.address))
        .times(INIT_INTEREST_RATE)
        .times(timeInYears);
      if (mintAmount.gt(0)) {
        await stablecoin.mint(vault.address, num2str(mintAmount));
      }
    }
  };

  return {
    deployMoneyMarket,
    timePass
  };
};

const moneyMarketModuleList = (module.exports.moneyMarketModuleList = [
  {
    name: "Aave",
    moduleGenerator: aaveMoneyMarketModule
  },
  {
    name: "B.Protocol",
    moduleGenerator: bProtocolMoneyMarketModule
  },
  {
    name: "CompoundERC20",
    moduleGenerator: compoundERC20MoneyMarketModule
  },
  {
    name: "CreamERC20",
    moduleGenerator: creamERC20MoneyMarketModule
  },
  {
    name: "Harvest",
    moduleGenerator: harvestMoneyMarketModule
  },
  {
    name: "YVault",
    moduleGenerator: yvaultMoneyMarketModule
  }
]);

const setupTest = (module.exports.setupTest = async (
  accounts,
  moneyMarketModule
) => {
  let stablecoin;
  let dInterestPool;
  let market;
  let feeModel;
  let interestModel;
  let interestOracle;
  let depositNFT;
  let fundingMultitoken;
  let mph;
  let mphMinter;
  let vesting02;
  let factory;
  let lens;

  // Accounts
  const acc0 = accounts[0];
  const acc1 = accounts[1];
  const acc2 = accounts[2];
  const govTreasury = accounts[3];
  const devWallet = accounts[4];

  const INIT_INTEREST_RATE = 0.1; // 10% APY
  const INIT_INTEREST_RATE_PER_SECOND = 0.1 / YEAR_IN_SEC; // 10% APY

  stablecoin = await ERC20Mock.new();

  // Mint stablecoin
  const mintAmount = 1000 * STABLECOIN_PRECISION;
  await stablecoin.mint(acc0, num2str(mintAmount));
  await stablecoin.mint(acc1, num2str(mintAmount));
  await stablecoin.mint(acc2, num2str(mintAmount));

  // Initialize MPH
  mph = await MPHToken.new();
  await mph.initialize();
  vesting02 = await Vesting02.new();
  await vesting02.initialize(mph.address, "Vested MPH", "veMPH");
  mphMinter = await MPHMinter.new();
  await mphMinter.initialize(
    mph.address,
    govTreasury,
    devWallet,
    vesting02.address,
    DevRewardMultiplier,
    GovRewardMultiplier
  );
  await vesting02.setMPHMinter(mphMinter.address);
  await mph.transferOwnership(mphMinter.address);
  await mphMinter.grantRole(WHITELISTER_ROLE, acc0, { from: acc0 });

  // Set infinite MPH approval
  await mph.approve(mphMinter.address, INF, { from: acc0 });
  await mph.approve(mphMinter.address, INF, { from: acc1 });
  await mph.approve(mphMinter.address, INF, { from: acc2 });

  // Deploy factory
  factory = await Factory.new();

  feeModel = await PercentageFeeModel.new(
    govTreasury,
    interestFee,
    earlyWithdrawFee
  );
  interestModel = await LinearDecayInterestModel.new(
    num2str(multiplierIntercept),
    num2str(multiplierSlope)
  );
  lens = await DInterestLens.new();

  const deployDInterest = async () => {
    let market, depositNFT, fundingMultitoken, interestOracle, dInterestPool;

    // Deploy moneyMarket
    market = await moneyMarketModule.deployMoneyMarket(
      accounts,
      factory,
      stablecoin,
      govTreasury
    );

    // Initialize the NFTs
    const nftTemplate = await NFT.new();
    const depositNFTReceipt = await factory.createNFT(
      nftTemplate.address,
      DEFAULT_SALT,
      "88mph Deposit",
      "88mph-Deposit"
    );
    depositNFT = await factoryReceiptToContract(depositNFTReceipt, NFT);
    const fundingMultitokenTemplate = await FundingMultitoken.new();
    const erc20WrapperTemplate = await ERC20Wrapper.new();
    const fundingNFTReceipt = await factory.createFundingMultitoken(
      fundingMultitokenTemplate.address,
      DEFAULT_SALT,
      "https://api.88mph.app/funding-metadata/",
      [stablecoin.address, mph.address],
      erc20WrapperTemplate.address,
      true,
      "88mph Floating-rate Bond: ",
      "88MPH-FRB-",
      STABLECOIN_DECIMALS
    );
    fundingMultitoken = await factoryReceiptToContract(
      fundingNFTReceipt,
      FundingMultitoken
    );

    // Initialize the interest oracle
    const interestOracleTemplate = await EMAOracle.new();
    const interestOracleReceipt = await factory.createEMAOracle(
      interestOracleTemplate.address,
      DEFAULT_SALT,
      num2str((INIT_INTEREST_RATE * PRECISION) / YEAR_IN_SEC),
      EMAUpdateInterval,
      EMASmoothingFactor,
      EMAAverageWindowInIntervals,
      market.address
    );
    interestOracle = await factoryReceiptToContract(
      interestOracleReceipt,
      EMAOracle
    );

    const dInterestTemplate = await DInterest.new();
    const dInterestReceipt = await factory.createDInterest(
      dInterestTemplate.address,
      DEFAULT_SALT,
      MaxDepositPeriod,
      MinDepositAmount,
      stablecoin.address,
      feeModel.address,
      interestModel.address,
      interestOracle.address,
      depositNFT.address,
      fundingMultitoken.address,
      mphMinter.address
    );
    dInterestPool = await factoryReceiptToContract(dInterestReceipt, DInterest);

    // Set MPH minting multiplier for DInterest pool
    await mphMinter.grantRole(WHITELISTED_POOL_ROLE, dInterestPool.address, {
      from: acc0
    });
    await mphMinter.setPoolDepositorRewardMintMultiplier(
      dInterestPool.address,
      PoolDepositorRewardMintMultiplier
    );
    await mphMinter.setPoolFunderRewardMultiplier(
      dInterestPool.address,
      PoolFunderRewardMultiplier
    );

    // Transfer the ownership of the money market to the DInterest pool
    await market.transferOwnership(dInterestPool.address);

    // Transfer NFT ownerships to the DInterest pool
    await depositNFT.transferOwnership(dInterestPool.address);
    await fundingMultitoken.grantRole(
      MINTER_BURNER_ROLE,
      dInterestPool.address
    );
    await fundingMultitoken.grantRole(DIVIDEND_ROLE, dInterestPool.address);
    await fundingMultitoken.grantRole(DIVIDEND_ROLE, mphMinter.address);

    // set infinite approval to pool
    await stablecoin.approve(dInterestPool.address, INF, { from: acc0 });
    await stablecoin.approve(dInterestPool.address, INF, { from: acc1 });
    await stablecoin.approve(dInterestPool.address, INF, { from: acc2 });

    return {
      market,
      depositNFT,
      fundingMultitoken,
      interestOracle,
      dInterestPool
    };
  };
  const dInterestPoolDeployResult = await deployDInterest();
  market = dInterestPoolDeployResult.market;
  depositNFT = dInterestPoolDeployResult.depositNFT;
  fundingMultitoken = dInterestPoolDeployResult.fundingMultitoken;
  interestOracle = dInterestPoolDeployResult.interestOracle;
  dInterestPool = dInterestPoolDeployResult.dInterestPool;

  return {
    stablecoin,
    dInterestPool,
    market,
    feeModel,
    interestModel,
    interestOracle,
    depositNFT,
    fundingMultitoken,
    mph,
    mphMinter,
    vesting02,
    factory,
    lens,
    deployDInterest
  };
});
