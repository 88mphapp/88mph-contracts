// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./moneymarkets/IMoneyMarket.sol";
import "./models/fee/IFeeModel.sol";
import "./models/interest/IInterestModel.sol";
import "./tokens/DepositMultitoken.sol";
import "./tokens/FundingMultitoken.sol";
import "./rewards/MPHMinter.sol";
import "./models/interest-oracle/IInterestOracle.sol";
import "./libs/DecMath.sol";

/**
    @title DeLorean Interest -- It's coming back from the future!
    @author Zefram Lou
    @notice The main pool contract for fixed-rate deposits
    @dev The contract to interact with for most actions
 */
contract DInterest is ReentrancyGuard, Ownable {
    using SafeERC20 for ERC20;
    using Address for address;
    using DecMath for uint256;

    // Constants
    uint256 internal constant PRECISION = 10**18;
    uint256 internal constant EXTRA_PRECISION = 10**27; // used for sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex
    uint256 internal constant ULTRA_PRECISION = 2**128; // used for funding.principalPerToken and deposit.interestRateMultiplierIntercept

    // User deposit data
    // Each deposit has an ID used in the depositMultitoken, which is equal to its index in `deposits` plus 1
    struct Deposit {
        uint256 interestRate; // interestAmount = interestRate * depositAmount
        uint256 feeRate; // feeAmount = feeRate * interestAmount
        uint256 mphRewardRate; // mphRewardAmount = mphRewardRate * depositAmount
        uint256 maturationTimestamp; // Unix timestamp after which the deposit may be withdrawn, in seconds
        uint256 depositTimestamp; // Unix timestamp at time of deposit, in seconds
        uint256 averageRecordedIncomeIndex; // Average income index at time of deposit, used for computing deposit surplus
        uint256 lastTopupTimestamp; // Unix timestamp of the last topup
        uint256 interestRateMultiplierIntercept; // the interest rate multiplier at the time of the last topup
        uint256 fundingID;
    }
    Deposit[] internal deposits;

    // Funding data
    // Each funding has an ID used in the fundingMultitoken, which is equal to its index in `fundingList` plus 1
    struct Funding {
        uint256 depositID;
        uint256 recordedMoneyMarketIncomeIndex; // the income index at the last update (creation or withdrawal)
        uint256 principalPerToken; // The amount of stablecoins that's earning interest for you per funding token you own. Scaled to 18 decimals regardless of stablecoin decimals.
    }
    Funding[] internal fundingList;
    // the sum of (recordedFundedPrincipalAmount / recordedMoneyMarketIncomeIndex) of all fundings
    uint256 public sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex;

    // Params
    uint256 public MaxDepositPeriod; // Maximum deposit period, in seconds
    uint256 public MinDepositAmount; // Minimum deposit amount

    // Instance variables
    uint256 public totalDeposit;
    uint256 public totalInterestOwed;
    uint256 public totalFeeOwed;
    uint256 public totalFundedPrincipalAmount;

    // External smart contracts
    IMoneyMarket public moneyMarket;
    ERC20 public stablecoin;
    IFeeModel public feeModel;
    IInterestModel public interestModel;
    IInterestOracle public interestOracle;
    DepositMultitoken public depositMultitoken;
    FundingMultitoken public fundingMultitoken;
    MPHMinter public mphMinter;

    // Events
    event EDeposit(
        address indexed sender,
        uint256 indexed depositID,
        uint256 depositAmount,
        uint256 interestAmount,
        uint256 feeAmount,
        uint256 mintMPHAmount,
        uint256 maturationTimestamp
    );
    event ETopupDeposit(
        address indexed sender,
        uint256 indexed depositID,
        uint256 depositAmount,
        uint256 interestAmount,
        uint256 feeAmount,
        uint256 mintMPHAmount
    );
    event ERolloverDeposit(
        address indexed sender,
        uint256 indexed depositID,
        uint256 indexed newDepositID,
        uint256 depositAmount
    );
    event EWithdraw(
        address indexed sender,
        uint256 indexed depositID,
        uint256 tokenAmount,
        uint256 feeAmount
    );
    event EFund(
        address indexed sender,
        uint256 indexed fundingID,
        uint256 fundAmount,
        uint256 tokenAmount
    );
    event ESetParamAddress(
        address indexed sender,
        string indexed paramName,
        address newValue
    );
    event ESetParamUint(
        address indexed sender,
        string indexed paramName,
        uint256 newValue
    );

    constructor(
        uint256 _MaxDepositPeriod,
        uint256 _MinDepositAmount,
        address _moneyMarket, // Address of IMoneyMarket that's used for generating interest (owner must be set to this DInterest contract)
        address _stablecoin, // Address of the stablecoin used to store funds
        address _feeModel, // Address of the FeeModel contract that determines how fees are charged
        address _interestModel, // Address of the InterestModel contract that determines how much interest to offer
        address _interestOracle, // Address of the InterestOracle contract that provides the average interest rate
        address _depositMultitoken, // Address of the ERC1155 multitoken representing ownership of deposits (this DInterest contract must have mint & burn roles)
        address _fundingMultitoken, // Address of the NFT representing ownership of fundings (owner must be set to this DInterest contract)
        address _mphMinter // Address of the contract for handling minting MPH to users
    ) {
        // Verify input addresses
        require(
            _moneyMarket.isContract() &&
                _stablecoin.isContract() &&
                _feeModel.isContract() &&
                _interestModel.isContract() &&
                _interestOracle.isContract() &&
                _depositMultitoken.isContract() &&
                _fundingMultitoken.isContract() &&
                _mphMinter.isContract(),
            "DInterest: An input address is not a contract"
        );

        moneyMarket = IMoneyMarket(_moneyMarket);
        stablecoin = ERC20(_stablecoin);
        feeModel = IFeeModel(_feeModel);
        interestModel = IInterestModel(_interestModel);
        interestOracle = IInterestOracle(_interestOracle);
        depositMultitoken = DepositMultitoken(_depositMultitoken);
        fundingMultitoken = FundingMultitoken(_fundingMultitoken);
        mphMinter = MPHMinter(_mphMinter);

        // Ensure moneyMarket uses the same stablecoin
        require(
            address(moneyMarket.stablecoin()) == _stablecoin,
            "DInterest: moneyMarket.stablecoin() != _stablecoin"
        );

        // Ensure interestOracle uses the same moneyMarket
        require(
            address(interestOracle.moneyMarket()) == _moneyMarket,
            "DInterest: interestOracle.moneyMarket() != _moneyMarket"
        );

        MaxDepositPeriod = _MaxDepositPeriod;
        MinDepositAmount = _MinDepositAmount;
    }

    /**
        Public actions
     */

    function deposit(uint256 depositAmount, uint256 maturationTimestamp)
        external
        nonReentrant
        returns (uint256 depositID)
    {
        return _deposit(depositAmount, maturationTimestamp, false);
    }

    function topupDeposit(uint256 depositID, uint256 depositAmount)
        external
        nonReentrant
    {
        _topupDeposit(depositID, depositAmount);
    }

    function rolloverDeposit(uint256 depositID, uint256 maturationTimestamp)
        external
        nonReentrant
    {
        _rolloverDeposit(depositID, maturationTimestamp);
    }

    function withdraw(uint256 depositID, uint256 tokenAmount)
        external
        nonReentrant
        returns (uint256 withdrawnStablecoinAmount)
    {
        return _withdraw(depositID, tokenAmount);
    }

    function multiDeposit(
        uint256[] calldata amountList,
        uint256[] calldata maturationTimestampList
    ) external nonReentrant returns (uint256[] memory depositIDList) {
        require(
            amountList.length == maturationTimestampList.length,
            "DInterest: List lengths unequal"
        );
        depositIDList = new uint256[](amountList.length);
        for (uint256 i = 0; i < amountList.length; i++) {
            depositIDList[i] = _deposit(
                amountList[i],
                maturationTimestampList[i],
                false
            );
        }
    }

    function multiTopupDeposit(
        uint256[] calldata depositIDList,
        uint256[] calldata depositAmountList
    ) external nonReentrant {
        require(
            depositIDList.length == depositAmountList.length,
            "DInterest: List lengths unequal"
        );
        for (uint256 i = 0; i < depositIDList.length; i++) {
            _topupDeposit(depositIDList[i], depositAmountList[i]);
        }
    }

    function multiRolloverDeposit(
        uint256[] calldata depositIDList,
        uint256[] calldata maturationTimestampList
    ) external nonReentrant {
        require(
            depositIDList.length == maturationTimestampList.length,
            "DInterest: List lengths unequal"
        );
        for (uint256 i = 0; i < depositIDList.length; i++) {
            _rolloverDeposit(depositIDList[i], maturationTimestampList[i]);
        }
    }

    function multiWithdraw(
        uint256[] calldata depositIDList,
        uint256[] calldata tokenAmountList
    )
        external
        nonReentrant
        returns (uint256[] memory withdrawnStablecoinAmountList)
    {
        require(
            depositIDList.length == tokenAmountList.length,
            "DInterest: List lengths unequal"
        );
        withdrawnStablecoinAmountList = new uint256[](depositIDList.length);
        for (uint256 i = 0; i < depositIDList.length; i++) {
            withdrawnStablecoinAmountList[i] = _withdraw(
                depositIDList[i],
                tokenAmountList[i]
            );
        }
    }

    /**
        Deficit funding
     */

    function fund(uint256 depositID, uint256 fundAmount)
        external
        nonReentrant
        returns (uint256 fundingID)
    {
        return _fund(depositID, fundAmount);
    }

    function payInterestToFunder(uint256 fundingID)
        external
        returns (uint256 interestAmount)
    {
        Funding storage f = _getFunding(fundingID);
        uint256 recordedMoneyMarketIncomeIndex =
            f.recordedMoneyMarketIncomeIndex;
        uint256 currentMoneyMarketIncomeIndex = moneyMarket.incomeIndex();
        uint256 fundingTokenTotalSupply =
            fundingMultitoken.totalSupply(fundingID);
        uint256 recordedFundedPrincipalAmount =
            (fundingTokenTotalSupply * f.principalPerToken) / ULTRA_PRECISION;

        // Update funding values
        sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex =
            sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex +
            (recordedFundedPrincipalAmount * EXTRA_PRECISION) /
            currentMoneyMarketIncomeIndex -
            (recordedFundedPrincipalAmount * EXTRA_PRECISION) /
            recordedMoneyMarketIncomeIndex;
        f.recordedMoneyMarketIncomeIndex = currentMoneyMarketIncomeIndex;

        // Compute interest to funders
        interestAmount =
            (recordedFundedPrincipalAmount * currentMoneyMarketIncomeIndex) /
            recordedMoneyMarketIncomeIndex -
            recordedFundedPrincipalAmount;

        // Distribute interest to funders
        if (interestAmount > 0) {
            interestAmount = moneyMarket.withdraw(interestAmount);
            if (interestAmount > 0) {
                stablecoin.safeIncreaseAllowance(
                    address(fundingMultitoken),
                    interestAmount
                );
                fundingMultitoken.distributeDividends(
                    fundingID,
                    interestAmount
                );
            }
        }
    }

    /**
        Public getters
     */

    function calculateInterestAmount(
        uint256 depositAmount,
        uint256 depositPeriodInSeconds
    ) public returns (uint256 interestAmount) {
        (, uint256 moneyMarketInterestRatePerSecond) =
            interestOracle.updateAndQuery();
        (bool surplusIsNegative, uint256 surplusAmount) = surplus();

        return
            interestModel.calculateInterestAmount(
                depositAmount,
                depositPeriodInSeconds,
                moneyMarketInterestRatePerSecond,
                surplusIsNegative,
                surplusAmount
            );
    }

    /**
        @notice Computes the floating interest amount owed to deficit funders, which will be paid out
                when a funded deposit is withdrawn.
                Formula: \sum_i recordedFundedPrincipalAmount_i * (incomeIndex / recordedMoneyMarketIncomeIndex_i - 1)
                = incomeIndex * (\sum_i recordedFundedPrincipalAmount_i / recordedMoneyMarketIncomeIndex_i)
                - \sum_i recordedFundedPrincipalAmount_i
                where i refers to a funding
     */
    function totalInterestOwedToFunders()
        public
        returns (uint256 interestOwed)
    {
        uint256 currentValue =
            (moneyMarket.incomeIndex() *
                sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex) /
                EXTRA_PRECISION;
        uint256 initialValue = totalFundedPrincipalAmount;
        if (currentValue < initialValue) {
            return 0;
        }
        return currentValue - initialValue;
    }

    function surplus() public returns (bool isNegative, uint256 surplusAmount) {
        uint256 totalValue = moneyMarket.totalValue();
        uint256 totalOwed =
            totalDeposit +
                totalInterestOwed +
                totalFeeOwed +
                totalInterestOwedToFunders();
        if (totalValue >= totalOwed) {
            // Locked value more than owed deposits, positive surplus
            isNegative = false;
            surplusAmount = totalValue - totalOwed;
        } else {
            // Locked value less than owed deposits, negative surplus
            isNegative = true;
            surplusAmount = totalOwed - totalValue;
        }
    }

    function rawSurplusOfDeposit(uint256 depositID)
        public
        returns (bool isNegative, uint256 surplusAmount)
    {
        Deposit storage depositEntry = _getDeposit(depositID);
        uint256 currentMoneyMarketIncomeIndex = moneyMarket.incomeIndex();
        uint256 depositTokenTotalSupply =
            depositMultitoken.totalSupply(depositID);
        uint256 depositAmount =
            depositTokenTotalSupply.decdiv(
                depositEntry.interestRate + PRECISION
            );
        uint256 interestAmount = depositTokenTotalSupply - depositAmount;
        uint256 feeAmount = interestAmount.decmul(depositEntry.feeRate);
        uint256 currentDepositValue =
            (depositAmount * currentMoneyMarketIncomeIndex) /
                depositEntry.averageRecordedIncomeIndex;
        uint256 owed = depositAmount + interestAmount + feeAmount;
        if (currentDepositValue >= owed) {
            // Locked value more than owed deposits, positive surplus
            isNegative = false;
            surplusAmount = currentDepositValue - owed;
        } else {
            // Locked value less than owed deposits, negative surplus
            isNegative = true;
            surplusAmount = owed - currentDepositValue;
        }
    }

    function surplusOfDeposit(uint256 depositID)
        public
        returns (bool isNegative, uint256 surplusAmount)
    {
        (isNegative, surplusAmount) = rawSurplusOfDeposit(depositID);

        uint256 totalPrincipal =
            _depositMultitokenToPrincipal(
                depositID,
                depositMultitoken.totalSupply(depositID)
            );
        uint256 fundingID = _getDeposit(depositID).fundingID;
        uint256 principalPerToken = _getFunding(fundingID).principalPerToken;
        uint256 unfundedPrincipalAmount =
            totalPrincipal -
                (fundingMultitoken.totalSupply(fundingID) * principalPerToken) /
                ULTRA_PRECISION;
        surplusAmount =
            (surplusAmount * unfundedPrincipalAmount) /
            totalPrincipal;
    }

    function fundingInterestAccrued(uint256 fundingID)
        external
        returns (uint256)
    {
        return _fundingInterestAccrued(fundingID);
    }

    function depositIsFunded(uint256 id) public view returns (bool) {
        return _getDeposit(id).fundingID > 0;
    }

    function depositsLength() external view returns (uint256) {
        return deposits.length;
    }

    function fundingListLength() external view returns (uint256) {
        return fundingList.length;
    }

    function getDeposit(uint256 depositID)
        external
        view
        returns (Deposit memory)
    {
        return deposits[depositID - 1];
    }

    function getFunding(uint256 fundingID)
        external
        view
        returns (Funding memory)
    {
        return fundingList[fundingID - 1];
    }

    function moneyMarketIncomeIndex() external returns (uint256) {
        return moneyMarket.incomeIndex();
    }

    function withdrawableAmountOfDeposit(
        uint256 depositID,
        uint256 tokenAmount,
        uint256 timestamp
    ) external view returns (uint256 withdrawableAmount, uint256 feeAmount) {
        // Verify input
        Deposit memory depositEntry = _getDeposit(depositID);
        if (
            tokenAmount == 0 ||
            timestamp <= depositEntry.depositTimestamp ||
            timestamp <= depositEntry.lastTopupTimestamp
        ) {
            return (0, 0);
        }

        // Load data to memory to save gas
        uint256 depositTokenTotalSupply =
            depositMultitoken.totalSupply(depositID);

        // Compute token amounts
        uint256 depositAmount =
            tokenAmount.decdiv(depositEntry.interestRate + PRECISION);
        uint256 interestAmount;
        // Limit scope to avoid stack too deep error
        {
            uint256 currentTimestamp =
                timestamp <= depositEntry.maturationTimestamp
                    ? timestamp
                    : depositEntry.maturationTimestamp;
            uint256 fullInterestAmount = tokenAmount - depositAmount;
            interestAmount =
                (fullInterestAmount *
                    (currentTimestamp - depositEntry.depositTimestamp)) /
                (depositEntry.maturationTimestamp -
                    depositEntry.depositTimestamp);
            interestAmount =
                (interestAmount *
                    _getInterestRateMultiplier(
                        depositEntry.interestRateMultiplierIntercept,
                        depositEntry.maturationTimestamp,
                        currentTimestamp,
                        depositEntry.lastTopupTimestamp
                    )) /
                ULTRA_PRECISION;
        }
        feeAmount = interestAmount.decmul(depositEntry.feeRate);
        withdrawableAmount = depositAmount + interestAmount;
    }

    /**
        Param setters
     */
    function setFeeModel(address newValue) external onlyOwner {
        require(newValue.isContract(), "DInterest: not contract");
        feeModel = IFeeModel(newValue);
        emit ESetParamAddress(msg.sender, "feeModel", newValue);
    }

    function setInterestModel(address newValue) external onlyOwner {
        require(newValue.isContract(), "DInterest: not contract");
        interestModel = IInterestModel(newValue);
        emit ESetParamAddress(msg.sender, "interestModel", newValue);
    }

    function setInterestOracle(address newValue) external onlyOwner {
        require(newValue.isContract(), "DInterest: not contract");
        interestOracle = IInterestOracle(newValue);
        require(
            interestOracle.moneyMarket() == moneyMarket,
            "DInterest: moneyMarket mismatch"
        );
        emit ESetParamAddress(msg.sender, "interestOracle", newValue);
    }

    function setRewards(address newValue) external onlyOwner {
        require(newValue.isContract(), "DInterest: not contract");
        moneyMarket.setRewards(newValue);
        emit ESetParamAddress(msg.sender, "moneyMarket.rewards", newValue);
    }

    function setMPHMinter(address newValue) external onlyOwner {
        require(newValue.isContract(), "DInterest: not contract");
        mphMinter = MPHMinter(newValue);
        emit ESetParamAddress(msg.sender, "mphMinter", newValue);
    }

    function setMaxDepositPeriod(uint256 newValue) external onlyOwner {
        require(newValue > 0, "DInterest: invalid value");
        MaxDepositPeriod = newValue;
        emit ESetParamUint(msg.sender, "MaxDepositPeriod", newValue);
    }

    function setMinDepositAmount(uint256 newValue) external onlyOwner {
        require(newValue > 0, "DInterest: invalid value");
        MinDepositAmount = newValue;
        emit ESetParamUint(msg.sender, "MinDepositAmount", newValue);
    }

    /**
        Internal getters
     */

    function _getDeposit(uint256 depositID)
        internal
        view
        returns (Deposit storage)
    {
        return deposits[depositID - 1];
    }

    function _getFunding(uint256 fundingID)
        internal
        view
        returns (Funding storage)
    {
        return fundingList[fundingID - 1];
    }

    function _depositMultitokenToPrincipal(
        uint256 depositID,
        uint256 multitokenAmount
    ) internal view returns (uint256) {
        Deposit storage depositEntry = _getDeposit(depositID);
        uint256 depositInterestRate = depositEntry.interestRate;
        return
            multitokenAmount.decdiv(depositInterestRate + PRECISION).decmul(
                depositInterestRate +
                    depositInterestRate.decmul(depositEntry.feeRate) +
                    PRECISION
            );
    }

    function _getInterestRateMultiplier(
        uint256 interestRateMultiplierIntercept,
        uint256 maturationTimestamp,
        uint256 currentTimestamp,
        uint256 lastTopupTimestamp
    ) internal pure returns (uint256) {
        return
            ((PRECISION - interestRateMultiplierIntercept) *
                (currentTimestamp - lastTopupTimestamp)) /
            (maturationTimestamp - lastTopupTimestamp) +
            interestRateMultiplierIntercept;
    }

    /**
        Internals
     */

    function _deposit(
        uint256 depositAmount,
        uint256 maturationTimestamp,
        bool rollover
    ) internal returns (uint256 depositID) {
        // Ensure input is valid
        require(
            depositAmount >= MinDepositAmount,
            "DInterest: Deposit amount too small"
        );
        uint256 depositPeriod = maturationTimestamp - block.timestamp;
        require(
            depositPeriod <= MaxDepositPeriod,
            "DInterest: Deposit period too long"
        );

        // Calculate interest
        uint256 interestAmount =
            calculateInterestAmount(depositAmount, depositPeriod);
        require(interestAmount > 0, "DInterest: interestAmount == 0");

        // Calculate fee
        uint256 feeAmount = feeModel.getFee(interestAmount);
        interestAmount -= feeAmount;

        // Mint MPH for msg.sender
        // TODO
        uint256 mintMPHAmount =
            mphMinter.mintDepositorReward(
                msg.sender,
                depositAmount,
                depositPeriod,
                interestAmount
            );

        // Record deposit data
        uint256 incomeIndex = moneyMarket.incomeIndex();
        deposits.push(
            Deposit({
                interestRate: interestAmount.decdiv(depositAmount),
                feeRate: feeAmount.decdiv(interestAmount),
                mphRewardRate: mintMPHAmount.decdiv(depositAmount),
                maturationTimestamp: maturationTimestamp,
                depositTimestamp: block.timestamp,
                fundingID: 0,
                averageRecordedIncomeIndex: incomeIndex,
                lastTopupTimestamp: block.timestamp,
                interestRateMultiplierIntercept: ULTRA_PRECISION
            })
        );

        // Update global values
        totalDeposit += depositAmount;
        totalInterestOwed += interestAmount;
        totalFeeOwed += feeAmount;

        // Only transfer funds from sender if it's not a rollover
        // because if it is the funds are already in the contract
        if (!rollover) {
            // Transfer `depositAmount` stablecoin to DInterest
            stablecoin.safeTransferFrom(
                msg.sender,
                address(this),
                depositAmount
            );
        }

        // Lend `depositAmount` stablecoin to money market
        stablecoin.safeIncreaseAllowance(address(moneyMarket), depositAmount);
        moneyMarket.deposit(depositAmount);

        depositID = deposits.length;

        // Mint depositMultitoken
        depositMultitoken.mint(
            msg.sender,
            depositID,
            depositAmount + interestAmount
        );

        // Emit event
        emit EDeposit(
            msg.sender,
            depositID,
            depositAmount,
            interestAmount,
            feeAmount,
            mintMPHAmount,
            maturationTimestamp
        );
    }

    function _topupDeposit(uint256 depositID, uint256 depositAmount) internal {
        Deposit memory depositEntry = _getDeposit(depositID);
        require(
            depositMultitoken.balanceOf(msg.sender, depositID) > 0,
            "DInterest: not owner"
        );

        // underflow check prevents topups after maturation
        uint256 depositPeriod =
            depositEntry.maturationTimestamp - block.timestamp;

        // Calculate interest
        uint256 interestAmount =
            calculateInterestAmount(depositAmount, depositPeriod);
        require(interestAmount > 0, "DInterest: interestAmount == 0");

        // Calculate fee
        uint256 feeAmount = feeModel.getFee(interestAmount);
        interestAmount -= feeAmount;

        // Mint MPH for msg.sender
        // TODO
        uint256 mintMPHAmount =
            mphMinter.mintDepositorReward(
                msg.sender,
                depositAmount,
                depositPeriod,
                interestAmount
            );

        // Record deposit data
        uint256 depositTokenTotalSupply =
            depositMultitoken.totalSupply(depositID);
        uint256 currentDepositAmount =
            depositTokenTotalSupply.decdiv(
                depositEntry.interestRate + PRECISION
            );
        uint256 currentInterestAmount =
            depositTokenTotalSupply - currentDepositAmount;
        depositEntry.interestRate =
            (PRECISION *
                interestAmount +
                currentDepositAmount *
                depositEntry.interestRate) /
            (depositAmount + currentDepositAmount);
        depositEntry.feeRate =
            (PRECISION *
                feeAmount +
                currentInterestAmount *
                depositEntry.feeRate) /
            (interestAmount + currentInterestAmount);
        depositEntry.mphRewardRate =
            (depositAmount *
                mintMPHAmount.decdiv(depositAmount) +
                currentDepositAmount *
                depositEntry.mphRewardRate) /
            (depositAmount + currentDepositAmount);
        uint256 sumOfRecordedDepositAmountDivRecordedIncomeIndex =
            (currentDepositAmount * EXTRA_PRECISION) /
                depositEntry.averageRecordedIncomeIndex +
                (depositAmount * EXTRA_PRECISION) /
                moneyMarket.incomeIndex();
        depositEntry.averageRecordedIncomeIndex =
            ((depositAmount + currentDepositAmount) * EXTRA_PRECISION) /
            sumOfRecordedDepositAmountDivRecordedIncomeIndex;
        depositEntry.interestRateMultiplierIntercept =
            (_getInterestRateMultiplier(
                depositEntry.interestRateMultiplierIntercept,
                depositEntry.maturationTimestamp,
                block.timestamp,
                depositEntry.lastTopupTimestamp
            ) * currentInterestAmount) /
            (interestAmount + currentInterestAmount);
        depositEntry.lastTopupTimestamp = block.timestamp;

        deposits[depositID - 1] = depositEntry;

        // Update global values
        totalDeposit += depositAmount;
        totalInterestOwed += interestAmount;
        totalFeeOwed += feeAmount;

        // Transfer `depositAmount` stablecoin to DInterest
        stablecoin.safeTransferFrom(msg.sender, address(this), depositAmount);

        // Lend `depositAmount` stablecoin to money market
        stablecoin.safeIncreaseAllowance(address(moneyMarket), depositAmount);
        moneyMarket.deposit(depositAmount);

        // Mint depositMultitoken
        depositMultitoken.mint(
            msg.sender,
            depositID,
            depositAmount + interestAmount
        );

        // Emit event
        emit ETopupDeposit(
            msg.sender,
            depositID,
            depositAmount,
            interestAmount,
            feeAmount,
            mintMPHAmount
        );
    }

    function _rolloverDeposit(uint256 depositID, uint256 maturationTimestamp)
        internal
        returns (uint256 newDepositID)
    {
        // withdraw from existing deposit
        uint256 withdrawnStablecoinAmount =
            _withdraw(
                depositID,
                depositMultitoken.balanceOf(msg.sender, depositID)
            );

        // deposit funds into a new deposit
        newDepositID = _deposit(
            withdrawnStablecoinAmount,
            maturationTimestamp,
            true
        );

        emit ERolloverDeposit(
            msg.sender,
            depositID,
            newDepositID,
            withdrawnStablecoinAmount
        );
    }

    function _withdraw(uint256 depositID, uint256 tokenAmount)
        internal
        returns (uint256 withdrawnStablecoinAmount)
    {
        // Verify input
        require(tokenAmount > 0, "DInterest: 0 amount");
        Deposit memory depositEntry = _getDeposit(depositID);
        require(
            block.timestamp > depositEntry.depositTimestamp,
            "DInterest: Deposited in same block"
        );

        // Load data to memory to save gas
        uint256 depositTokenTotalSupply =
            depositMultitoken.totalSupply(depositID);

        // Compute token amounts
        uint256 depositAmount =
            tokenAmount.decdiv(depositEntry.interestRate + PRECISION);
        uint256 interestAmount;
        // Limit scope to avoid stack too deep error
        {
            uint256 currentTimestamp =
                block.timestamp <= depositEntry.maturationTimestamp
                    ? block.timestamp
                    : depositEntry.maturationTimestamp;
            uint256 fullInterestAmount = tokenAmount - depositAmount;
            interestAmount =
                (fullInterestAmount *
                    (currentTimestamp - depositEntry.depositTimestamp)) /
                (depositEntry.maturationTimestamp -
                    depositEntry.depositTimestamp);
            interestAmount =
                (interestAmount *
                    _getInterestRateMultiplier(
                        depositEntry.interestRateMultiplierIntercept,
                        depositEntry.maturationTimestamp,
                        currentTimestamp,
                        depositEntry.lastTopupTimestamp
                    )) /
                ULTRA_PRECISION;

            // Update global values
            totalDeposit -= depositAmount;
            totalInterestOwed -= fullInterestAmount;
            totalFeeOwed -= fullInterestAmount.decmul(depositEntry.feeRate);
        }
        uint256 feeAmount = interestAmount.decmul(depositEntry.feeRate);

        // If deposit was funded, compute funding interest payout
        uint256 fundingInterestAmount;
        if (depositEntry.fundingID > 0) {
            Funding storage funding = _getFunding(depositEntry.fundingID);

            // Compute funded deposit amount before withdrawal
            uint256 fundingTokenTotalSupply =
                fundingMultitoken.totalSupply(depositEntry.fundingID);
            uint256 recordedFundedPrincipalAmount =
                (fundingTokenTotalSupply * funding.principalPerToken) /
                    ULTRA_PRECISION;

            // Shrink funding principal per token value
            funding.principalPerToken =
                (funding.principalPerToken *
                    (depositTokenTotalSupply - tokenAmount)) /
                depositTokenTotalSupply;

            // Compute interest payout + refund
            // and update relevant state
            fundingInterestAmount = _computeAndUpdateFundingInterestAfterWithdraw(
                depositEntry.fundingID,
                recordedFundedPrincipalAmount,
                tokenAmount,
                interestAmount
            );
        }

        // Burn `tokenAmount` depositMultitoken
        depositMultitoken.burn(msg.sender, depositID, tokenAmount);

        // Withdraw funds from money market
        // Withdraws principal together with funding interest to save gas
        uint256 withdrawAmount =
            moneyMarket.withdraw(
                depositAmount +
                    interestAmount +
                    feeAmount +
                    fundingInterestAmount
            );

        // We do this instead of `depositAmount + interestAmount` because `withdrawAmount` might
        // be slightly less due to rounding
        withdrawnStablecoinAmount =
            withdrawAmount -
            feeAmount -
            fundingInterestAmount;
        stablecoin.safeTransfer(msg.sender, withdrawnStablecoinAmount);

        // Emit event
        emit EWithdraw(msg.sender, depositID, tokenAmount, feeAmount);

        // Send `feeAmount` stablecoin to feeModel beneficiary
        if (feeAmount > 0) {
            stablecoin.safeTransfer(feeModel.beneficiary(), feeAmount);
        }

        // Distribute `fundingInterestAmount` stablecoins to funders
        if (fundingInterestAmount > 0) {
            stablecoin.safeIncreaseAllowance(
                address(fundingMultitoken),
                fundingInterestAmount
            );
            fundingMultitoken.distributeDividends(
                depositEntry.fundingID,
                fundingInterestAmount
            );
        }
    }

    function _fund(uint256 depositID, uint256 fundAmount)
        internal
        returns (uint256 fundingID)
    {
        Deposit storage depositEntry = _getDeposit(depositID);

        (bool isNegative, uint256 surplusMagnitude) = surplus();
        require(isNegative, "DInterest: No deficit available");

        (isNegative, surplusMagnitude) = rawSurplusOfDeposit(depositID);
        require(isNegative, "DInterest: No deficit available");
        if (fundAmount > surplusMagnitude) {
            fundAmount = surplusMagnitude;
        }

        // Create funding struct if one doesn't exist
        uint256 incomeIndex = moneyMarket.incomeIndex();
        require(incomeIndex > 0, "DInterest: incomeIndex == 0");
        uint256 totalPrincipal =
            _depositMultitokenToPrincipal(
                depositID,
                depositMultitoken.totalSupply(depositID)
            );
        uint256 totalPrincipalToFund;
        fundingID = depositEntry.fundingID;
        uint256 mintTokenAmount;
        if (fundingID == 0) {
            // The first funder, create struct
            fundingList.push(
                Funding({
                    depositID: depositID,
                    recordedMoneyMarketIncomeIndex: incomeIndex,
                    principalPerToken: ULTRA_PRECISION
                })
            );
            fundingID = fundingList.length;
            depositEntry.fundingID = fundingID;
            totalPrincipalToFund =
                (totalPrincipal * fundAmount) /
                surplusMagnitude;
            mintTokenAmount = totalPrincipalToFund;
        } else {
            // Not the first funder
            // Compute amount of principal to fund
            uint256 principalPerToken =
                _getFunding(fundingID).principalPerToken;
            uint256 unfundedPrincipalAmount =
                totalPrincipal -
                    (fundingMultitoken.totalSupply(fundingID) *
                        principalPerToken) /
                    ULTRA_PRECISION;
            surplusMagnitude =
                (surplusMagnitude * unfundedPrincipalAmount) /
                totalPrincipal;
            if (fundAmount > surplusMagnitude) {
                fundAmount = surplusMagnitude;
            }
            totalPrincipalToFund =
                (unfundedPrincipalAmount * fundAmount) /
                surplusMagnitude;
            mintTokenAmount =
                (totalPrincipalToFund * ULTRA_PRECISION) /
                principalPerToken;
        }
        // Mint funding multitoken
        fundingMultitoken.mint(msg.sender, fundingID, mintTokenAmount);

        // Update relevant values
        sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex +=
            (totalPrincipalToFund * EXTRA_PRECISION) /
            incomeIndex;
        totalFundedPrincipalAmount += totalPrincipalToFund;

        // Transfer `fundAmount` stablecoins from msg.sender
        stablecoin.safeTransferFrom(msg.sender, address(this), fundAmount);

        // Deposit `fundAmount` stablecoins into moneyMarket
        stablecoin.safeIncreaseAllowance(address(moneyMarket), fundAmount);
        moneyMarket.deposit(fundAmount);

        // Emit event
        emit EFund(msg.sender, fundingID, fundAmount, mintTokenAmount);
    }

    function _computeAndUpdateFundingInterestAfterWithdraw(
        uint256 fundingID,
        uint256 recordedFundedPrincipalAmount,
        uint256 tokenAmount,
        uint256 interestAmount
    ) internal returns (uint256 fundingInterestAmount) {
        Funding storage f = _getFunding(fundingID);
        uint256 recordedMoneyMarketIncomeIndex =
            f.recordedMoneyMarketIncomeIndex;
        uint256 currentMoneyMarketIncomeIndex = moneyMarket.incomeIndex();
        require(
            currentMoneyMarketIncomeIndex > 0,
            "DInterest: currentMoneyMarketIncomeIndex == 0"
        );
        uint256 currentFundedPrincipalAmount =
            (fundingMultitoken.totalSupply(fundingID) * f.principalPerToken) /
                ULTRA_PRECISION;

        // Update funding values
        sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex =
            sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex +
            (currentFundedPrincipalAmount * EXTRA_PRECISION) /
            currentMoneyMarketIncomeIndex -
            (recordedFundedPrincipalAmount * EXTRA_PRECISION) /
            recordedMoneyMarketIncomeIndex;
        f.recordedMoneyMarketIncomeIndex = currentMoneyMarketIncomeIndex;
        totalFundedPrincipalAmount -=
            recordedFundedPrincipalAmount -
            currentFundedPrincipalAmount;

        // Compute interest to funders
        fundingInterestAmount =
            (recordedFundedPrincipalAmount * currentMoneyMarketIncomeIndex) /
            recordedMoneyMarketIncomeIndex -
            recordedFundedPrincipalAmount;

        // Add refund to interestAmount
        uint256 depositID = f.depositID;
        uint256 depositAmount =
            tokenAmount.decdiv(_getDeposit(depositID).interestRate + PRECISION);
        fundingInterestAmount +=
            ((_depositMultitokenToPrincipal(depositID, tokenAmount) -
                depositAmount -
                interestAmount -
                interestAmount.decmul(_getDeposit(depositID).feeRate)) *
                recordedFundedPrincipalAmount) /
            _depositMultitokenToPrincipal(
                depositID,
                depositMultitoken.totalSupply(depositID)
            );

        // Mint funder rewards
        // TODO
        /*mphMinter.mintFunderReward(
            funder,
            depositAmount,
            f.creationTimestamp,
            depositMaturationTimestamp,
            interestAmount,
            early
        );*/
    }

    function _fundingInterestAccrued(uint256 fundingID)
        internal
        returns (uint256 fundingInterestAmount)
    {
        Funding storage f = _getFunding(fundingID);
        uint256 fundingTokenTotalSupply =
            fundingMultitoken.totalSupply(fundingID);
        uint256 recordedFundedPrincipalAmount =
            (fundingTokenTotalSupply * f.principalPerToken) / ULTRA_PRECISION;
        uint256 recordedMoneyMarketIncomeIndex =
            f.recordedMoneyMarketIncomeIndex;
        uint256 currentMoneyMarketIncomeIndex = moneyMarket.incomeIndex();
        require(
            currentMoneyMarketIncomeIndex > 0,
            "DInterest: currentMoneyMarketIncomeIndex == 0"
        );

        // Compute interest to funders
        fundingInterestAmount =
            (recordedFundedPrincipalAmount * currentMoneyMarketIncomeIndex) /
            recordedMoneyMarketIncomeIndex -
            recordedFundedPrincipalAmount;
    }
}
