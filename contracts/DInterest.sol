pragma solidity 0.5.15;
pragma experimental ABIEncoderV2;

import "@nomiclabs/buidler/console.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./libs/DecMath.sol";
import "./moneymarkets/IMoneyMarket.sol";
import "./FeeModel.sol";

// DeLorean Interest -- It's coming back from the future!
// EL PSY CONGROO
// Author: Zefram Lou
// Contact: zefram@baconlabs.dev
contract DInterest is ReentrancyGuard {
    using SafeMath for uint256;
    using DecMath for uint256;
    using SafeERC20 for ERC20Detailed;

    // Constants
    uint256 internal constant PRECISION = 10**18;
    uint256 internal constant ONE = 10**18;

    // Used for maintaining an accurate average block time
    uint256 internal _blocktime; // Number of seconds needed to generate each block, decimal
    uint256 internal _lastCallBlock; // Last block when the contract was called
    uint256 internal _lastCallTimestamp; // Last timestamp when the contract was called
    uint256 internal _numBlocktimeDatapoints; // Number of block time datapoints collected
    modifier updateBlocktime {
        if (block.number > _lastCallBlock) {
            uint256 blocksSinceLastCall = block.number.sub(_lastCallBlock);
            // newBlockTime = (now - _lastCallTimestamp) / (block.number - _lastCallBlock)
            // decimal
            uint256 newBlocktime = now.sub(_lastCallTimestamp).decdiv(
                blocksSinceLastCall
            );
            // _blocktime = (blocksSinceLastCall * newBlocktime + _numBlocktimeDatapoints * _blocktime) / (_numBlocktimeDatapoints + blocksSinceLastCall)
            // decimal
            _blocktime = _blocktime
                .mul(_numBlocktimeDatapoints)
                .add(newBlocktime.mul(blocksSinceLastCall))
                .div(_numBlocktimeDatapoints.add(blocksSinceLastCall));
            _lastCallBlock = block.number;
            _lastCallTimestamp = now;
            _numBlocktimeDatapoints = _numBlocktimeDatapoints.add(
                blocksSinceLastCall
            );
        }
        _;
    }

    // User deposit data
    struct Deposit {
        uint256 amount; // Amount of stablecoin deposited
        uint256 maturationTimestamp; // Unix timestamp after which the deposit may be withdrawn, in seconds
        bool active; // True if not yet withdrawn, false if withdrawn
    }
    mapping(address => Deposit[]) public userDeposits;
    mapping(address => Deposit[]) public sponsorDeposits;

    // Params
    uint256 public UIRMultiplier; // Upfront interest rate multiplier
    uint256 public MinDepositPeriod; // Minimum deposit period, in seconds

    // Instance variables
    uint256 public totalDeposit;

    // External smart contracts
    IMoneyMarket public moneyMarket;
    ERC20Detailed public stablecoin;
    FeeModel public feeModel;

    // Events
    event EDeposit(
        address indexed sender,
        uint256 depositID,
        uint256 amount,
        uint256 maturationTimestamp,
        uint256 upfrontInterestAmount
    );
    event EWithdraw(address indexed sender, uint256 depositID);
    event ESponsorDeposit(
        address indexed sender,
        uint256 depositID,
        uint256 amount,
        uint256 maturationTimestamp,
        string data
    );
    event ESponsorWithdraw(address indexed sender, uint256 depositID);

    constructor(
        uint256 _UIRMultiplier,
        uint256 _MinDepositPeriod,
        address _moneyMarket,
        address _stablecoin,
        address _feeModel
    ) public {
        _blocktime = 15 * PRECISION; // Default block time is 15 seconds
        _lastCallBlock = block.number;
        _lastCallTimestamp = now;
        _numBlocktimeDatapoints = 10**6; // Start with many datapoints to prevent initial fluctuation

        UIRMultiplier = _UIRMultiplier;
        MinDepositPeriod = _MinDepositPeriod;

        totalDeposit = 0;

        moneyMarket = IMoneyMarket(_moneyMarket);
        stablecoin = ERC20Detailed(_stablecoin);
        feeModel = FeeModel(_feeModel);
    }

    /**
        Public actions
     */

    function deposit(uint256 amount, uint256 maturationTimestamp)
        external
        updateBlocktime
        nonReentrant
    {
        _deposit(amount, maturationTimestamp);
    }

    function withdraw(uint256 depositID) external updateBlocktime nonReentrant {
        _withdraw(depositID);
    }

    function multiDeposit(
        uint256[] calldata amountList,
        uint256[] calldata maturationTimestampList
    ) external updateBlocktime nonReentrant {
        require(
            amountList.length == maturationTimestampList.length,
            "DInterest: List lengths unequal"
        );
        for (uint256 i = 0; i < amountList.length; i = i.add(1)) {
            _deposit(amountList[i], maturationTimestampList[i]);
        }
    }

    function multiWithdraw(uint256[] calldata depositIDList)
        external
        updateBlocktime
        nonReentrant
    {
        for (uint256 i = 0; i < depositIDList.length; i = i.add(1)) {
            _withdraw(depositIDList[i]);
        }
    }

    /**
        Public getters
     */

    function calculateUpfrontInterestRate(uint256 depositPeriodInSeconds)
        public
        view
        returns (uint256 upfrontInterestRate)
    {
        uint256 moneyMarketInterestRatePerSecond = moneyMarket
            .supplyRatePerSecond(_blocktime);

        // upfrontInterestRate = (1 - 1 / (1 + moneyMarketInterestRatePerSecond * depositPeriodInSeconds * UIRMultiplier))
        upfrontInterestRate = ONE.sub(
            ONE.decdiv(
                ONE.add(
                    moneyMarketInterestRatePerSecond
                        .mul(depositPeriodInSeconds)
                        .decmul(UIRMultiplier)
                )
            )
        );
    }

    function blocktime() external view returns (uint256) {
        return _blocktime;
    }

    function deficit()
        external
        view
        returns (bool isNegative, uint256 deficitAmount)
    {
        uint256 totalValue = moneyMarket.totalValue();
        if (totalValue >= totalDeposit) {
            isNegative = false;
            deficitAmount = totalValue.sub(totalDeposit);
        } else {
            isNegative = true;
            deficitAmount = totalDeposit.sub(totalValue);
        }
    }

    /**
        Sponsor actions
     */

    function sponsorDeposit(
        uint256 amount,
        uint256 maturationTimestamp,
        string calldata data
    ) external updateBlocktime nonReentrant {
        // Ensure deposit period is at least MinDepositPeriod
        uint256 depositPeriod = maturationTimestamp.sub(now);
        require(
            depositPeriod >= MinDepositPeriod,
            "DInterest: Deposit period too short"
        );

        // Transfer `amount` stablecoin from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Record deposit data for `msg.sender`
        sponsorDeposits[msg.sender].push(
            Deposit({
                amount: amount,
                maturationTimestamp: maturationTimestamp,
                active: true
            })
        );

        // Update totalDeposit
        totalDeposit = totalDeposit.add(amount);

        // Lend `amount` stablecoin to money market
        if (stablecoin.allowance(address(this), address(moneyMarket)) > 0) {
            stablecoin.safeApprove(address(moneyMarket), 0);
        }
        stablecoin.safeApprove(address(moneyMarket), amount);
        moneyMarket.deposit(amount);

        // Emit event
        emit ESponsorDeposit(
            msg.sender,
            sponsorDeposits[msg.sender].length.sub(1),
            amount,
            maturationTimestamp,
            data
        );
    }

    function sponsorWithdraw(uint256 depositID)
        external
        updateBlocktime
        nonReentrant
    {
        Deposit memory depositEntry = sponsorDeposits[msg.sender][depositID];

        // Verify deposit is active and set to inactive
        require(depositEntry.active, "DInterest: Deposit not active");
        depositEntry.active = false;

        // Verify `now >= depositEntry.maturationTimestamp`
        require(
            now >= depositEntry.maturationTimestamp,
            "DInterest: Deposit not mature"
        );

        // Update totalDeposit
        totalDeposit = totalDeposit.sub(depositEntry.amount);

        // Withdraw `depositEntry.amount` stablecoin from money market
        moneyMarket.withdraw(depositEntry.amount);

        // Send `depositEntry.amount` stablecoin to `msg.sender`
        stablecoin.safeTransfer(msg.sender, depositEntry.amount);

        // Emit event
        emit ESponsorWithdraw(msg.sender, depositID);
    }

    /**
        Internals
     */

    function _deposit(uint256 amount, uint256 maturationTimestamp) internal {
        // Ensure deposit period is at least MinDepositPeriod
        uint256 depositPeriod = maturationTimestamp.sub(now);
        require(
            depositPeriod >= MinDepositPeriod,
            "DInterest: Deposit period too short"
        );

        // Transfer `amount` stablecoin from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Record deposit data for `msg.sender`
        userDeposits[msg.sender].push(
            Deposit({
                amount: amount,
                maturationTimestamp: maturationTimestamp,
                active: true
            })
        );

        // Update totalDeposit
        totalDeposit = totalDeposit.add(amount);

        // Send feeAmount stablecoin to beneficiary
        uint256 feeAmount = feeModel.getFee(amount);
        stablecoin.safeTransfer(feeModel.beneficiary(), feeAmount);

        // Calculate `upfrontInterestAmount` stablecoin to return to `msg.sender`
        uint256 amountAfterFee = amount.sub(feeAmount);
        uint256 upfrontInterestRate = calculateUpfrontInterestRate(
            depositPeriod
        );
        uint256 upfrontInterestAmount = amountAfterFee.decmul(upfrontInterestRate);

        // Lend `amountAfterFee - upfrontInterestAmount` stablecoin to money market
        uint256 principalAmount = amountAfterFee.sub(upfrontInterestAmount);
        if (stablecoin.allowance(address(this), address(moneyMarket)) > 0) {
            stablecoin.safeApprove(address(moneyMarket), 0);
        }
        stablecoin.safeApprove(address(moneyMarket), principalAmount);
        moneyMarket.deposit(principalAmount);

        // Send `upfrontInterestAmount` stablecoin to `msg.sender`
        stablecoin.safeTransfer(msg.sender, upfrontInterestAmount);

        // Emit event
        emit EDeposit(
            msg.sender,
            userDeposits[msg.sender].length.sub(1),
            amount,
            maturationTimestamp,
            upfrontInterestAmount
        );
    }

    function _withdraw(uint256 depositID) internal {
        Deposit memory depositEntry = userDeposits[msg.sender][depositID];

        // Verify deposit is active and set to inactive
        require(depositEntry.active, "DInterest: Deposit not active");
        depositEntry.active = false;

        // Verify `now >= depositEntry.maturationTimestamp`
        require(
            now >= depositEntry.maturationTimestamp,
            "DInterest: Deposit not mature"
        );

        // Update totalDeposit
        totalDeposit = totalDeposit.sub(depositEntry.amount);

        // Withdraw `depositEntry.amount` stablecoin from money market
        moneyMarket.withdraw(depositEntry.amount);

        // Send `depositEntry.amount` stablecoin to `msg.sender`
        stablecoin.safeTransfer(msg.sender, depositEntry.amount);

        // Emit event
        emit EWithdraw(msg.sender, depositID);
    }
}
