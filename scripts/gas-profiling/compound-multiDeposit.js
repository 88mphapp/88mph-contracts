const env = require("@nomiclabs/buidler");
const BigNumber = require("bignumber.js");

async function main() {
    const accounts = await env.web3.eth.getAccounts();

    // Contract artifacts
    const DInterest = artifacts.require('DInterest')
    const FeeModel = artifacts.require('FeeModel')
    const AaveMarket = artifacts.require('AaveMarket')
    const CompoundERC20Market = artifacts.require('CompoundERC20Market')
    const NFT = artifacts.require('NFT')
    const CERC20Mock = artifacts.require('CERC20Mock')
    const ComptrollerMock = artifacts.require('ComptrollerMock')
    const ERC20Mock = artifacts.require('ERC20Mock')
    const ATokenMock = artifacts.require('ATokenMock')
    const LendingPoolMock = artifacts.require('LendingPoolMock')
    const LendingPoolCoreMock = artifacts.require('LendingPoolCoreMock')
    const LendingPoolAddressesProviderMock = artifacts.require('LendingPoolAddressesProviderMock')

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
    let cToken
    let dInterestPool
    let market
    let comptroller
    let comp
    let feeModel
    let depositNFT
    let fundingNFT

    // Constants
    const INIT_EXRATE = 2e26 // 1 cToken = 0.02 stablecoin
    const INIT_INTEREST_RATE = 0.1 // 10% APY
    const INIT_INTEREST_RATE_PER_BLOCK = 45290900000

    // Initialize mock stablecoin and cToken
    stablecoin = await ERC20Mock.new()
    cToken = await CERC20Mock.new(stablecoin.address)

    // Mint stablecoin
    const mintAmount = 1000 * PRECISION
    await stablecoin.mint(cToken.address, num2str(mintAmount))
    await stablecoin.mint(acc0, num2str(mintAmount))
    await stablecoin.mint(acc1, num2str(mintAmount))
    await stablecoin.mint(acc2, num2str(mintAmount))

    // Initialize the money market
    feeModel = await FeeModel.new()
    comp = await ERC20Mock.new()
    comptroller = await ComptrollerMock.new(comp.address)
    market = await CompoundERC20Market.new(cToken.address, comptroller.address, feeModel.address, stablecoin.address)

    // Initialize the NFTs
    depositNFT = await NFT.new('88mph Deposit', '88mph-Deposit')
    fundingNFT = await NFT.new('88mph Funding', '88mph-Funding')

    // Initialize the DInterest pool
    dInterestPool = await DInterest.new(UIRMultiplier, MinDepositPeriod, MaxDepositAmount, market.address, stablecoin.address, feeModel.address, depositNFT.address, fundingNFT.address)

    // Transfer the ownership of the money market to the DInterest pool
    await market.transferOwnership(dInterestPool.address)

    // Transfer NFT ownerships to the DInterest pool
    await depositNFT.transferOwnership(dInterestPool.address)
    await fundingNFT.transferOwnership(dInterestPool.address)

    // BEGINING OF TEST

    const depositAmount = PRECISION
    const blockNow = await latestBlockTimestamp()

    const multiDepositInputSize = 38
    await stablecoin.approve(dInterestPool.address, num2str(depositAmount * multiDepositInputSize), { from: acc0 })
    const multiDepositResult = await dInterestPool.multiDeposit(Array(multiDepositInputSize).fill(num2str(depositAmount)), Array(multiDepositInputSize).fill(blockNow + YEAR_IN_SEC), { from: acc0 })
    const multiDepositGas = multiDepositResult.receipt.cumulativeGasUsed
    console.log(`Compound multiDeposit(): inputSize=${multiDepositInputSize}, gasUsed=${multiDepositGas}`);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
