pragma solidity 0.6.5;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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
    using SafeERC20 for ERC20;

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
        uint256 id; // ID unique among all deposits & all users, starts from 1
        uint256 amount; // Amount of stablecoin deposited
        uint256 maturationTimestamp; // Unix timestamp after which the deposit may be withdrawn, in seconds
        uint256 initialDeficit; // Deficit incurred to the pool at time of deposit
        bool active; // True if not yet withdrawn, false if withdrawn
    }
    mapping(address => Deposit[]) public userDeposits;
    uint256 public latestUserDepositID; // the ID of the most recently created userDeposit
    uint256 public latestFundedUserDepositID; // the ID of the most recently created userDeposit that was funded
    uint256 public unfundedUserDepositAmount; // the deposited stablecoin amount whose deficit hasn't been funded

    // Funding data
    struct Funding {
        // deposits with fromDepositID < ID <= toDepositID are funded
        uint256 fromDepositID;
        uint256 toDepositID;
        uint256 recordedFundedDepositAmount;
        uint256 recordedMoneyMarketPrice;
        address interestReceipient;
        address owner; // can change owner & interestReceipient
    }
    Funding[] public fundingList;

    // Params
    uint256 public immutable UIRMultiplier; // Upfront interest rate multiplier
    uint256 public immutable MinDepositPeriod; // Minimum deposit period, in seconds
    uint256 public immutable MaxDepositAmount; // Maximum deposit amount for each deposit, in stablecoins

    // Instance variables
    uint256 public totalDeposit;

    // External smart contracts
    IMoneyMarket public immutable moneyMarket;
    ERC20 public immutable stablecoin;
    FeeModel public immutable feeModel;

    // Events
    event EDeposit(
        address indexed sender,
        uint256 depositIdx,
        uint256 amount,
        uint256 maturationTimestamp,
        uint256 upfrontInterestAmount
    );
    event EWithdraw(address indexed sender, uint256 depositIdx, bool early);
    event EFund(
        address indexed sender,
        uint256 fundingIdx,
        uint256 deficitAmount
    );
    event EFundingSetOwner(address newOwner);
    event EFundingSetInterestReceipient(address newInterestReceipient);

    constructor(
        uint256 _UIRMultiplier,
        uint256 _MinDepositPeriod,
        uint256 _MaxDepositAmount,
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
        MaxDepositAmount = _MaxDepositAmount;

        totalDeposit = 0;
        moneyMarket = IMoneyMarket(_moneyMarket);
        stablecoin = ERC20(_stablecoin);
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

    function withdraw(uint256 depositIdx, uint256 fundingIdx)
        external
        updateBlocktime
        nonReentrant
    {
        _withdraw(depositIdx, fundingIdx);
    }

    function earlyWithdraw(uint256 depositIdx, uint256 fundingIdx)
        external
        updateBlocktime
        nonReentrant
    {
        _earlyWithdraw(depositIdx, fundingIdx);
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

    function multiWithdraw(
        uint256[] calldata depositIdxList,
        uint256[] calldata fundingIdxList
    ) external updateBlocktime nonReentrant {
        require(
            depositIdxList.length == fundingIdxList.length,
            "DInterest: List lengths unequal"
        );
        for (uint256 i = 0; i < depositIdxList.length; i = i.add(1)) {
            _withdraw(depositIdxList[i], fundingIdxList[i]);
        }
    }

    function multiEarlyWithdraw(
        uint256[] calldata depositIdxList,
        uint256[] calldata fundingIdxList
    ) external updateBlocktime nonReentrant {
        require(
            depositIdxList.length == fundingIdxList.length,
            "DInterest: List lengths unequal"
        );
        for (uint256 i = 0; i < depositIdxList.length; i = i.add(1)) {
            _earlyWithdraw(depositIdxList[i], fundingIdxList[i]);
        }
    }

    /**
        Deficit funding
     */

    function fund(address interestReceipient)
        external
        updateBlocktime
        nonReentrant
    {
        // Calculate current deficit
        (bool isNegative, uint256 deficit) = surplus();
        require(isNegative, "DInterest: No deficit available");
        require(
            !userDepositIsFunded(latestUserDepositID),
            "DInterest: All deposits funded"
        );

        // Create funding struct
        fundingList.push(
            Funding({
                fromDepositID: latestFundedUserDepositID,
                toDepositID: latestUserDepositID,
                recordedFundedDepositAmount: unfundedUserDepositAmount,
                recordedMoneyMarketPrice: moneyMarket.price(),
                interestReceipient: interestReceipient,
                owner: msg.sender
            })
        );

        // Update relevant values
        latestFundedUserDepositID = latestUserDepositID;
        unfundedUserDepositAmount = 0;

        // Transfer `deficit` stablecoins from msg.sender
        stablecoin.safeTransferFrom(msg.sender, address(this), deficit);

        // Deposit `deficit` stablecoins into moneyMarket
        if (stablecoin.allowance(address(this), address(moneyMarket)) > 0) {
            stablecoin.safeApprove(address(moneyMarket), 0);
        }
        stablecoin.safeApprove(address(moneyMarket), deficit);
        moneyMarket.deposit(deficit);

        // Emit event
        emit EFund(msg.sender, fundingList.length.sub(1), deficit);
        emit EFundingSetOwner(msg.sender);
        emit EFundingSetInterestReceipient(interestReceipient);
    }

    function fundingSetOwner(uint256 fundingIdx, address newOwner)
        external
        updateBlocktime
        nonReentrant
    {
        require(newOwner != address(0), "DInterest: newOwner == 0");
        Funding storage f = fundingList[fundingIdx];
        require(f.owner == msg.sender, "DInterest: Not funding owner");
        f.owner = newOwner;
        emit EFundingSetOwner(newOwner);
    }

    function fundingRenounceOwnership(uint256 fundingIdx)
        external
        updateBlocktime
        nonReentrant
    {
        Funding storage f = fundingList[fundingIdx];
        require(f.owner == msg.sender, "DInterest: Not funding owner");
        f.owner = address(0);
        emit EFundingSetOwner(address(0));
    }

    function fundingSetInterestReceipient(
        uint256 fundingIdx,
        address newInterestReceipient
    ) external updateBlocktime nonReentrant {
        require(newInterestReceipient != address(0), "DInterest: newInterestReceipient == 0");
        Funding storage f = fundingList[fundingIdx];
        require(f.owner == msg.sender, "DInterest: Not funding owner");
        f.interestReceipient = newInterestReceipient;
        emit EFundingSetInterestReceipient(newInterestReceipient);
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

    function surplus()
        public
        view
        returns (bool isNegative, uint256 surplusAmount)
    {
        uint256 totalValue = moneyMarket.totalValue();
        if (totalValue >= totalDeposit) {
            // Locked value more than owed deposits, positive surplus
            isNegative = false;
            surplusAmount = totalValue.sub(totalDeposit);
        } else {
            // Locked value less than owed deposits, negative surplus
            isNegative = true;
            surplusAmount = totalDeposit.sub(totalValue);
        }
    }

    function userDepositIsFunded(uint256 id) public view returns (bool) {
        return (id <= latestFundedUserDepositID);
    }

    /**
        Internals
     */

    function _deposit(uint256 amount, uint256 maturationTimestamp) internal {
        // Ensure deposit amount is not more than maximum
        require(amount <= MaxDepositAmount, "DInterest: Deposit amount exceeds max");

        // Ensure deposit period is at least MinDepositPeriod
        uint256 depositPeriod = maturationTimestamp.sub(now);
        require(
            depositPeriod >= MinDepositPeriod,
            "DInterest: Deposit period too short"
        );

        // Transfer `amount` stablecoin from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Update totalDeposit
        totalDeposit = totalDeposit.add(amount);

        // Update funding related data
        uint256 id = latestUserDepositID.add(1);
        latestUserDepositID = id;
        unfundedUserDepositAmount = unfundedUserDepositAmount.add(amount);

        // Calculate `upfrontInterestAmount` stablecoin to return to `msg.sender`
        uint256 upfrontInterestRate = calculateUpfrontInterestRate(
            depositPeriod
        );
        uint256 upfrontInterestAmount = amount.decmul(upfrontInterestRate);
        uint256 feeAmount = feeModel.getFee(upfrontInterestAmount);

        // Record deposit data for `msg.sender`
        userDeposits[msg.sender].push(
            Deposit({
                id: id,
                amount: amount,
                maturationTimestamp: maturationTimestamp,
                initialDeficit: upfrontInterestAmount,
                active: true
            })
        );

        // Deduct `feeAmount` from `upfrontInterestAmount`
        upfrontInterestAmount = upfrontInterestAmount.sub(feeAmount);

        // Lend `amount - upfrontInterestAmount` stablecoin to money market
        uint256 principalAmount = amount.sub(upfrontInterestAmount).sub(
            feeAmount
        );
        if (stablecoin.allowance(address(this), address(moneyMarket)) > 0) {
            stablecoin.safeApprove(address(moneyMarket), 0);
        }
        stablecoin.safeApprove(address(moneyMarket), principalAmount);
        moneyMarket.deposit(principalAmount);

        // Send `feeAmount` stablecoin to `feeModel.beneficiary()`
        stablecoin.safeTransfer(feeModel.beneficiary(), feeAmount);

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

    function _withdraw(uint256 depositIdx, uint256 fundingIdx) internal {
        Deposit storage depositEntry = userDeposits[msg.sender][depositIdx];

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

        // If deposit was funded, payout interest to funder
        if (userDepositIsFunded(depositEntry.id)) {
            Funding storage f = fundingList[fundingIdx];
            require(
                depositEntry.id > f.fromDepositID &&
                    depositEntry.id <= f.toDepositID,
                "DInterest: Deposit not funded by fundingIdx"
            );
            uint256 currentMoneyMarketPrice = moneyMarket.price();
            uint256 interestAmount = f
                .recordedFundedDepositAmount
                .mul(currentMoneyMarketPrice)
                .div(f.recordedMoneyMarketPrice)
                .sub(f.recordedFundedDepositAmount);

            // Update funding values
            f.recordedFundedDepositAmount = f.recordedFundedDepositAmount.sub(
                depositEntry.amount
            );
            f.recordedMoneyMarketPrice = currentMoneyMarketPrice;

            // Send interest
            stablecoin.safeTransfer(f.interestReceipient, interestAmount);
        }

        // Send `depositEntry.amount` stablecoin to `msg.sender`
        stablecoin.safeTransfer(msg.sender, depositEntry.amount);

        // Emit event
        emit EWithdraw(msg.sender, depositIdx, false);
    }

    function _earlyWithdraw(uint256 depositIdx, uint256 fundingIdx) internal {
        Deposit storage depositEntry = userDeposits[msg.sender][depositIdx];

        // Verify deposit is active and set to inactive
        require(depositEntry.active, "DInterest: Deposit not active");
        depositEntry.active = false;

        // Transfer `depositEntry.initialDeficit` from `msg.sender`
        stablecoin.safeTransferFrom(
            msg.sender,
            address(this),
            depositEntry.initialDeficit
        );

        // Update totalDeposit
        totalDeposit = totalDeposit.sub(depositEntry.amount);

        // Withdraw `depositEntry.amount` stablecoin from money market
        moneyMarket.withdraw(
            depositEntry.amount.sub(depositEntry.initialDeficit)
        );

        // If deposit was funded, payout initialDeficit + interest to funder
        if (userDepositIsFunded(depositEntry.id)) {
            Funding storage f = fundingList[fundingIdx];
            require(
                depositEntry.id > f.fromDepositID &&
                    depositEntry.id <= f.toDepositID,
                "DInterest: Deposit not funded by fundingIdx"
            );
            uint256 currentMoneyMarketPrice = moneyMarket.price();
            uint256 interestAmount = f
                .recordedFundedDepositAmount
                .mul(currentMoneyMarketPrice)
                .div(f.recordedMoneyMarketPrice)
                .sub(f.recordedFundedDepositAmount);

            // Update funding values
            f.recordedFundedDepositAmount = f.recordedFundedDepositAmount.sub(
                depositEntry.amount
            );
            f.recordedMoneyMarketPrice = currentMoneyMarketPrice;

            // Send initialDeficit + interest to funder
            stablecoin.safeTransfer(
                f.interestReceipient,
                interestAmount.add(depositEntry.initialDeficit)
            );
        }

        // Send `depositEntry.amount` stablecoin to `msg.sender`
        stablecoin.safeTransfer(msg.sender, depositEntry.amount);

        // Emit event
        emit EWithdraw(msg.sender, depositIdx, true);
    }
}