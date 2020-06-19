const env = require("@nomiclabs/buidler");
const BigNumber = require("bignumber.js");

async function main() {
    const accounts = await env.web3.eth.getAccounts();

    // Contract artifacts
    const DInterest = env.artifacts.require('DInterest')
    const FeeModel = env.artifacts.require('FeeModel')
    const AaveMarket = env.artifacts.require('AaveMarket')
    const CompoundERC20Market = env.artifacts.require('CompoundERC20Market')
    const NFT = env.artifacts.require('NFT')
    const CERC20Mock = env.artifacts.require('CERC20Mock')
    const ERC20Mock = env.artifacts.require('ERC20Mock')
    const ATokenMock = env.artifacts.require('ATokenMock')
    const LendingPoolMock = env.artifacts.require('LendingPoolMock')
    const LendingPoolCoreMock = env.artifacts.require('LendingPoolCoreMock')
    const LendingPoolAddressesProviderMock = env.artifacts.require('LendingPoolAddressesProviderMock')

    // Constants
    const PRECISION = 1e18
    const UIRMultiplier = BigNumber(0.75 * 1e18).integerValue().toFixed() // Minimum safe avg interest rate multiplier
    const MinDepositPeriod = 90 * 24 * 60 * 60 // 90 days in seconds
    const MaxDepositAmount = BigNumber(1000 * PRECISION).toFixed() // 1000 stablecoins
    const YEAR_IN_BLOCKS = 2104400 // Number of blocks in a year
    const YEAR_IN_SEC = 31556952 // Number of seconds in a year
    const epsilon = 1e-6
    const INF = BigNumber(2).pow(256).minus(1).toFixed()

    // Utilities
    // travel `time` seconds forward in time
    function timeTravel(time) {
        return new Promise((resolve, reject) => {
            web3.currentProvider.send({
                jsonrpc: '2.0',
                method: 'evm_increaseTime',
                params: [time],
                id: new Date().getTime()
            }, (err, result) => {
                if (err)
                    return reject(err)
                return resolve(result)
            })
        })
    }

    async function latestBlockTimestamp() {
        return (await web3.eth.getBlock('latest')).timestamp
    }

    // Converts a JS number into a string that doesn't use scientific notation
    function num2str(num) {
        return BigNumber(num).integerValue().toFixed()
    }

    // Accounts
    const acc0 = accounts[0]
    const acc1 = accounts[1]
    const acc2 = accounts[2]

    // Contract instances
    let stablecoin
    let aToken
    let lendingPoolCore
    let lendingPool
    let lendingPoolAddressesProvider
    let dInterestPool
    let market
    let feeModel

    // Constants
    const INIT_INTEREST_RATE = 0.1 // 10% APY

    // Initialize mock stablecoin and Aave
    stablecoin = await ERC20Mock.new()
    aToken = await ATokenMock.new(stablecoin.address)
    lendingPoolCore = await LendingPoolCoreMock.new()
    lendingPool = await LendingPoolMock.new(lendingPoolCore.address)
    await lendingPoolCore.setLendingPool(lendingPool.address)
    await lendingPool.setReserveAToken(stablecoin.address, aToken.address)
    lendingPoolAddressesProvider = await LendingPoolAddressesProviderMock.new()
    await lendingPoolAddressesProvider.setLendingPoolImpl(lendingPool.address)
    await lendingPoolAddressesProvider.setLendingPoolCoreImpl(lendingPoolCore.address)

    // Mint stablecoin
    const mintAmount = 1000 * PRECISION
    await stablecoin.mint(aToken.address, num2str(mintAmount))
    await stablecoin.mint(acc0, num2str(mintAmount))
    await stablecoin.mint(acc1, num2str(mintAmount))
    await stablecoin.mint(acc2, num2str(mintAmount))

    // Initialize the money market
    market = await AaveMarket.new(lendingPoolAddressesProvider.address, stablecoin.address)

    // Initialize the NFTs
    depositNFT = await NFT.new('88mph Deposit', '88mph-Deposit')
    fundingNFT = await NFT.new('88mph Funding', '88mph-Funding')

    // Initialize the DInterest pool
    feeModel = await FeeModel.new()
    dInterestPool = await DInterest.new(UIRMultiplier, MinDepositPeriod, MaxDepositAmount, market.address, stablecoin.address, feeModel.address, depositNFT.address, fundingNFT.address)

    // Transfer the ownership of the money market to the DInterest pool
    await market.transferOwnership(dInterestPool.address)

    // Transfer NFT ownerships to the DInterest pool
    await depositNFT.transferOwnership(dInterestPool.address)
    await fundingNFT.transferOwnership(dInterestPool.address)

    // BEGINING OF TEST

    const depositAmount = PRECISION
    const blockNow = await latestBlockTimestamp()

    const multiWithdrawInputSize = 100
    const multiDepositInputSize = 32
    const numMultiDeposit = Math.floor(multiWithdrawInputSize / multiDepositInputSize)
    const numDeposit = multiWithdrawInputSize - numMultiDeposit * multiDepositInputSize
    await stablecoin.approve(dInterestPool.address, num2str(depositAmount * multiWithdrawInputSize), { from: acc1 })
    for (let i = 0; i < numMultiDeposit; i++) {
        await dInterestPool.multiDeposit(Array(multiDepositInputSize).fill(num2str(depositAmount)), Array(multiDepositInputSize).fill(blockNow + YEAR_IN_SEC), { from: acc1 })
    }
    await dInterestPool.multiDeposit(Array(numDeposit).fill(num2str(depositAmount)), Array(numDeposit).fill(blockNow + YEAR_IN_SEC), { from: acc1 })

    await stablecoin.approve(dInterestPool.address, INF, { from: acc0 })
    await dInterestPool.fundAll({ from: acc0 })

    await timeTravel(YEAR_IN_SEC)
    await aToken.mintInterest(num2str(YEAR_IN_SEC))

    const multiWithdrawResult = await dInterestPool.multiWithdraw(Array.from(new Array(multiWithdrawInputSize), (x, i) => i + 1), Array(multiWithdrawInputSize).fill(1), { from: acc1 })
    const multiWithdrawGas = multiWithdrawResult.receipt.cumulativeGasUsed
    console.log(`Aave multiWithdraw(): inputSize=${multiWithdrawInputSize}, gasUsed=${multiWithdrawGas}`);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
