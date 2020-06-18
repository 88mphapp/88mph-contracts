pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./libs/DecMath.sol";
import "./moneymarkets/IMoneyMarket.sol";
import "./FeeModel.sol";
import "./NFT.sol";


// DeLorean Interest -- It's coming back from the future!
// EL PSY CONGROO
// Author: Zefram Lou
// Contact: zefram@baconlabs.dev
contract DInterest is ReentrancyGuard {
    using SafeMath for uint256;
    using DecMath for uint256;
    using SafeERC20 for ERC20;
    using Address for address;

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
    // Each deposit has an ID used in the depositNFT, which is equal to its index in `deposits` plus 1
    struct Deposit {
        uint256 amount; // Amount of stablecoin deposited
        uint256 maturationTimestamp; // Unix timestamp after which the deposit may be withdrawn, in seconds
        uint256 initialDeficit; // Deficit incurred to the pool at time of deposit
        uint256 initialMoneyMarketPrice; // Money market's price at time of deposit
        bool active; // True if not yet withdrawn, false if withdrawn
    }
    Deposit[] internal deposits;
    uint256 public latestFundedDepositID; // the ID of the most recently created deposit that was funded
    uint256 public unfundedUserDepositAmount; // the deposited stablecoin amount whose deficit hasn't been funded

    // Funding data
    // Each funding has an ID used in the fundingNFT, which is equal to its index in `fundingList` plus 1
    struct Funding {
        // deposits with fromDepositID < ID <= toDepositID are funded
        uint256 fromDepositID;
        uint256 toDepositID;
        uint256 recordedFundedDepositAmount;
        uint256 recordedMoneyMarketPrice;
    }
    Funding[] internal fundingList;

    // Params
    uint256 public UIRMultiplier; // Upfront interest rate multiplier
    uint256 public MinDepositPeriod; // Minimum deposit period, in seconds
    uint256 public MaxDepositAmount; // Maximum deposit amount for each deposit, in stablecoins

    // Instance variables
    uint256 public totalDeposit;

    // External smart contracts
    IMoneyMarket public moneyMarket;
    ERC20 public stablecoin;
    FeeModel public feeModel;
    NFT public depositNFT;
    NFT public fundingNFT;

    // Events
    event EDeposit(
        address indexed sender,
        uint256 depositID,
        uint256 amount,
        uint256 maturationTimestamp,
        uint256 upfrontInterestAmount
    );
    event EWithdraw(address indexed sender, uint256 depositID, bool early);
    event EFund(
        address indexed sender,
        uint256 indexed fundingID,
        uint256 deficitAmount
    );

    constructor(
        uint256 _UIRMultiplier,
        uint256 _MinDepositPeriod,
        uint256 _MaxDepositAmount,
        address _moneyMarket,
        address _stablecoin,
        address _feeModel,
        address _depositNFT,
        address _fundingNFT
    ) public {
        // Verify input addresses
        require(
            _moneyMarket != address(0) && _stablecoin != address(0) && _feeModel != address(0) && _depositNFT != address(0) && _fundingNFT != address(0),
            "DInterest: An input address is 0"
        );
        require(
            _moneyMarket.isContract() && _stablecoin.isContract() && _feeModel.isContract() && _depositNFT.isContract() && _fundingNFT.isContract(),
            "DInterest: An input address is not a contract"
        );

        moneyMarket = IMoneyMarket(_moneyMarket);
        stablecoin = ERC20(_stablecoin);
        feeModel = FeeModel(_feeModel);
        depositNFT = NFT(_depositNFT);
        fundingNFT = NFT(_fundingNFT);

        // Ensure moneyMarket uses the same stablecoin
        require(moneyMarket.stablecoin() == _stablecoin, "DInterest: moneyMarket.stablecoin() != _stablecoin");

        _blocktime = 15 * PRECISION; // Default block time is 15 seconds
        _lastCallBlock = block.number;
        _lastCallTimestamp = now;
        _numBlocktimeDatapoints = 10**6; // Start with many datapoints to prevent initial fluctuation

        UIRMultiplier = _UIRMultiplier;
        MinDepositPeriod = _MinDepositPeriod;
        MaxDepositAmount = _MaxDepositAmount;
        totalDeposit = 0;
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

    function withdraw(uint256 depositID, uint256 fundingID)
        external
        updateBlocktime
        nonReentrant
    {
        _withdraw(depositID, fundingID);
    }

    function earlyWithdraw(uint256 depositID, uint256 fundingID)
        external
        updateBlocktime
        nonReentrant
    {
        _earlyWithdraw(depositID, fundingID);
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
        uint256[] calldata depositIDList,
        uint256[] calldata fundingIDList
    ) external updateBlocktime nonReentrant {
        require(
            depositIDList.length == fundingIDList.length,
            "DInterest: List lengths unequal"
        );
        for (uint256 i = 0; i < depositIDList.length; i = i.add(1)) {
            _withdraw(depositIDList[i], fundingIDList[i]);
        }
    }

    function multiEarlyWithdraw(
        uint256[] calldata depositIDList,
        uint256[] calldata fundingIDList
    ) external updateBlocktime nonReentrant {
        require(
            depositIDList.length == fundingIDList.length,
            "DInterest: List lengths unequal"
        );
        for (uint256 i = 0; i < depositIDList.length; i = i.add(1)) {
            _earlyWithdraw(depositIDList[i], fundingIDList[i]);
        }
    }

    /**
        Deficit funding
     */

    function fundAll() external updateBlocktime nonReentrant {
        // Calculate current deficit
        (bool isNegative, uint256 deficit) = surplus();
        require(isNegative, "DInterest: No deficit available");
        require(
            !depositIsFunded(deposits.length),
            "DInterest: All deposits funded"
        );

        // Create funding struct
        fundingList.push(
            Funding({
                fromDepositID: latestFundedDepositID,
                toDepositID: deposits.length,
                recordedFundedDepositAmount: unfundedUserDepositAmount,
                recordedMoneyMarketPrice: moneyMarket.price()
            })
        );

        // Update relevant values
        latestFundedDepositID = deposits.length;
        unfundedUserDepositAmount = 0;

        // Transfer `deficit` stablecoins from msg.sender
        stablecoin.safeTransferFrom(msg.sender, address(this), deficit);

        // Deposit `deficit` stablecoins into moneyMarket
        if (stablecoin.allowance(address(this), address(moneyMarket)) > 0) {
            stablecoin.safeIncreaseAllowance(address(moneyMarket), 0);
        }
        stablecoin.safeIncreaseAllowance(address(moneyMarket), deficit);
        moneyMarket.deposit(deficit);

        // Mint fundingNFT
        fundingNFT.mint(msg.sender, fundingList.length);

        // Emit event
        uint256 fundingID = fundingList.length;
        emit EFund(msg.sender, fundingID, deficit);
    }

    function fundMultiple(uint256 toDepositID)
        external
        updateBlocktime
        nonReentrant
    {
        require(toDepositID > latestFundedDepositID, "DInterest: Deposits already funded");
        require(toDepositID <= deposits.length, "DInterest: Invalid toDepositID");

        (bool isNegative, uint256 deficit) = surplus();
        require(isNegative, "DInterest: No deficit available");

        uint256 totalDeficit = 0;
        uint256 totalSurplus = 0;
        uint256 totalDepositToFund = 0;
        // Deposits with ID [latestFundedDepositID+1, toDepositID] will be funded
        for (uint256 id = latestFundedDepositID.add(1); id <= toDepositID; id = id.add(1)) {
            Deposit storage depositEntry = _getDeposit(id);

            (isNegative, deficit) = surplusOfDeposit(id);
            if (isNegative) {
                // Add on deficit to total
                totalDeficit = totalDeficit.add(deficit);
            } else {
                // Has surplus
                totalSurplus = totalSurplus.add(deficit);
            }
            totalDepositToFund = totalDepositToFund.add(depositEntry.amount);
        }
        if (totalSurplus >= totalDeficit) {
            // Deposits selected have a surplus as a whole, revert
            revert("DInterest: Selected deposits in surplus");
        } else {
            // Deduct surplus from totalDeficit
            totalDeficit = totalDeficit.sub(totalSurplus);
        }

        // Create funding struct
        fundingList.push(
            Funding({
                fromDepositID: latestFundedDepositID,
                toDepositID: toDepositID,
                recordedFundedDepositAmount: totalDepositToFund,
                recordedMoneyMarketPrice: moneyMarket.price()
            })
        );

        // Update relevant values
        latestFundedDepositID = toDepositID;
        unfundedUserDepositAmount = unfundedUserDepositAmount.sub(
            totalDepositToFund
        );

        // Transfer `totalDeficit` stablecoins from msg.sender
        stablecoin.safeTransferFrom(msg.sender, address(this), totalDeficit);

        // Deposit `totalDeficit` stablecoins into moneyMarket
        if (stablecoin.allowance(address(this), address(moneyMarket)) > 0) {
            stablecoin.safeIncreaseAllowance(address(moneyMarket), 0);
        }
        stablecoin.safeIncreaseAllowance(address(moneyMarket), totalDeficit);
        moneyMarket.deposit(totalDeficit);

        // Mint fundingNFT
        fundingNFT.mint(msg.sender, fundingList.length);

        // Emit event
        uint256 fundingID = fundingList.length;
        emit EFund(msg.sender, fundingID, totalDeficit);
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

    function surplusOfDeposit(uint256 depositID)
        public
        returns (bool isNegative, uint256 surplusAmount)
    {
        Deposit storage depositEntry = _getDeposit(depositID);
        uint256 currentMoneyMarketPrice = moneyMarket.price();
        uint256 currentDepositValue = depositEntry
            .amount
            .sub(depositEntry.initialDeficit)
            .mul(currentMoneyMarketPrice)
            .div(depositEntry.initialMoneyMarketPrice);
        if (currentDepositValue >= depositEntry.amount) {
            // Locked value more than owed deposits, positive surplus
            isNegative = false;
            surplusAmount = currentDepositValue.sub(depositEntry.amount);
        } else {
            // Locked value less than owed deposits, negative surplus
            isNegative = true;
            surplusAmount = depositEntry.amount.sub(currentDepositValue);
        }
    }

    function depositIsFunded(uint256 id) public view returns (bool) {
        return (id <= latestFundedDepositID);
    }

    function depositsLength() external view returns (uint256) {
        return deposits.length;
    }

    function fundingListLength() external view returns (uint256) {
        return fundingList.length;
    }

    function getDeposit(uint256 depositID) external view returns (Deposit memory) {
        return deposits[depositID.sub(1)];
    }

    function getFunding(uint256 fundingID) external view returns (Funding memory) {
        return fundingList[fundingID.sub(1)];
    }

    /**
        Internal getters
     */

    function _getDeposit(uint256 depositID) internal view returns (Deposit storage) {
        return deposits[depositID.sub(1)];
    }

    function _getFunding(uint256 fundingID) internal view returns (Funding storage) {
        return fundingList[fundingID.sub(1)];
    }

    /**
        Internals
     */

    function _deposit(uint256 amount, uint256 maturationTimestamp) internal {
        // Ensure deposit amount is not more than maximum
        require(
            amount <= MaxDepositAmount,
            "DInterest: Deposit amount exceeds max"
        );

        // Ensure deposit period is at least MinDepositPeriod
        uint256 depositPeriod = maturationTimestamp.sub(now);
        require(
            depositPeriod >= MinDepositPeriod,
            "DInterest: Deposit period too short"
        );

        // Update totalDeposit
        totalDeposit = totalDeposit.add(amount);

        // Update funding related data
        uint256 id = deposits.length.add(1);
        unfundedUserDepositAmount = unfundedUserDepositAmount.add(amount);

        // Calculate `upfrontInterestAmount` stablecoin to return to `msg.sender`
        uint256 upfrontInterestRate = calculateUpfrontInterestRate(
            depositPeriod
        );
        uint256 upfrontInterestAmount = amount.decmul(upfrontInterestRate);
        uint256 feeAmount = feeModel.getFee(upfrontInterestAmount);

        // Record deposit data for `msg.sender`
        deposits.push(
            Deposit({
                amount: amount,
                maturationTimestamp: maturationTimestamp,
                initialDeficit: upfrontInterestAmount,
                initialMoneyMarketPrice: moneyMarket.price(),
                active: true
            })
        );

        // Deduct `feeAmount` from `upfrontInterestAmount`
        upfrontInterestAmount = upfrontInterestAmount.sub(feeAmount);

        // Transfer `amount` stablecoin from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Lend `amount - upfrontInterestAmount` stablecoin to money market
        uint256 principalAmount = amount.sub(upfrontInterestAmount).sub(
            feeAmount
        );
        if (stablecoin.allowance(address(this), address(moneyMarket)) > 0) {
            stablecoin.safeIncreaseAllowance(address(moneyMarket), 0);
        }
        stablecoin.safeIncreaseAllowance(address(moneyMarket), principalAmount);
        moneyMarket.deposit(principalAmount);

        // Send `feeAmount` stablecoin to `feeModel.beneficiary()`
        stablecoin.safeTransfer(feeModel.beneficiary(), feeAmount);

        // Send `upfrontInterestAmount` stablecoin to `msg.sender`
        stablecoin.safeTransfer(msg.sender, upfrontInterestAmount);

        // Mint depositNFT
        depositNFT.mint(msg.sender, id);

        // Emit event
        emit EDeposit(
            msg.sender,
            id,
            amount,
            maturationTimestamp,
            upfrontInterestAmount
        );
    }

    function _withdraw(uint256 depositID, uint256 fundingID) internal {
        Deposit storage depositEntry = _getDeposit(depositID);

        // Verify deposit is active and set to inactive
        require(depositEntry.active, "DInterest: Deposit not active");
        depositEntry.active = false;

        // Verify `now >= depositEntry.maturationTimestamp`
        require(
            now >= depositEntry.maturationTimestamp,
            "DInterest: Deposit not mature"
        );

        // Verify msg.sender owns the depositNFT
        require(
            depositNFT.ownerOf(depositID) == msg.sender,
            "DInterest: Sender doesn't own depositNFT"
        );

        // Update totalDeposit
        totalDeposit = totalDeposit.sub(depositEntry.amount);

        // Burn depositNFT
        depositNFT.burn(depositID);

        // Withdraw `depositEntry.amount` stablecoin from money market
        moneyMarket.withdraw(depositEntry.amount);

        // If deposit was funded, payout interest to funder
        if (depositIsFunded(depositID)) {
            Funding storage f = _getFunding(fundingID);
            require(
                depositID > f.fromDepositID && depositID <= f.toDepositID,
                "DInterest: Deposit not funded by fundingID"
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

            // Withdraw `interestAmount` stablecoin from money market
            moneyMarket.withdraw(interestAmount);

            // Send interest
            stablecoin.safeTransfer(
                fundingNFT.ownerOf(fundingID),
                interestAmount
            );
        }

        // Send `depositEntry.amount` stablecoin to `msg.sender`
        stablecoin.safeTransfer(msg.sender, depositEntry.amount);

        // Emit event
        emit EWithdraw(msg.sender, depositID, false);
    }

    function _earlyWithdraw(uint256 depositID, uint256 fundingID) internal {
        Deposit storage depositEntry = _getDeposit(depositID);

        // Verify `now < depositEntry.maturationTimestamp`
        require(
            now < depositEntry.maturationTimestamp,
            "DInterest: Deposit mature, use withdraw() instead"
        );

        // Verify deposit is active and set to inactive
        require(depositEntry.active, "DInterest: Deposit not active");
        depositEntry.active = false;

        // Verify msg.sender owns the depositNFT
        require(
            depositNFT.ownerOf(depositID) == msg.sender,
            "DInterest: Sender doesn't own depositNFT"
        );

        // Update totalDeposit
        totalDeposit = totalDeposit.sub(depositEntry.amount);

        // Burn depositNFT
        depositNFT.burn(depositID);

        // Transfer `depositEntry.initialDeficit` from `msg.sender`
        stablecoin.safeTransferFrom(
            msg.sender,
            address(this),
            depositEntry.initialDeficit
        );

        // Withdraw `depositEntry.amount` stablecoin from money market
        moneyMarket.withdraw(
            depositEntry.amount.sub(depositEntry.initialDeficit)
        );

        // If deposit was funded, payout initialDeficit + interest to funder
        if (depositIsFunded(depositID)) {
            Funding storage f = _getFunding(fundingID);
            require(
                depositID > f.fromDepositID && depositID <= f.toDepositID,
                "DInterest: Deposit not funded by fundingID"
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

            // Withdraw `interestAmount` stablecoin from money market
            moneyMarket.withdraw(interestAmount);

            // Send initialDeficit + interest to funder
            stablecoin.safeTransfer(
                fundingNFT.ownerOf(fundingID),
                interestAmount.add(depositEntry.initialDeficit)
            );
        }

        // Send `depositEntry.amount` stablecoin to `msg.sender`
        stablecoin.safeTransfer(msg.sender, depositEntry.amount);

        // Emit event
        emit EWithdraw(msg.sender, depositID, true);
    }
}
