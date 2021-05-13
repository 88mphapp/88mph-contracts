// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "./moneymarkets/IMoneyMarket.sol";
import "./models/fee/IFeeModel.sol";
import "./models/interest/IInterestModel.sol";
import "./tokens/NFT.sol";
import "./tokens/FundingMultitoken.sol";
import "./rewards/MPHMinter.sol";
import "./models/interest-oracle/IInterestOracle.sol";
import "./libs/DecMath.sol";
import "hardhat/console.sol";

/**
    @title DeLorean Interest -- It's coming back from the future!
    @author Zefram Lou
    @notice The main pool contract for fixed-rate deposits
    @dev The contract to interact with for most actions
 */
contract DInterest is ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for ERC20Upgradeable;
    using AddressUpgradeable for address;
    using DecMath for uint256;

    // Constants
    uint256 internal constant PRECISION = 10**18;
    /**
        @dev used for sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex
     */
    uint256 internal constant EXTRA_PRECISION = 10**27;
    /**
        @dev used for funding.principalPerToken and deposit.interestRateMultiplierIntercept
     */
    uint256 internal constant ULTRA_PRECISION = 2**128;

    // User deposit data
    // Each deposit has an ID used in the depositNFT, which is equal to its index in `deposits` plus 1
    struct Deposit {
        uint256 virtualTokenTotalSupply; // depositAmount + interestAmount, behaves like a zero coupon bond
        uint256 interestRate; // interestAmount = interestRate * depositAmount
        uint256 feeRate; // feeAmount = feeRate * interestAmount
        uint256 averageRecordedIncomeIndex; // Average income index at time of deposit, used for computing deposit surplus
        uint64 maturationTimestamp; // Unix timestamp after which the deposit may be withdrawn, in seconds
        uint64 depositTimestamp; // Unix timestamp at time of deposit, in seconds
        uint64 fundingID; // The ID of the associated Funding struct. 0 if not funded.
    }
    Deposit[] internal deposits;

    // Funding data
    // Each funding has an ID used in the fundingMultitoken, which is equal to its index in `fundingList` plus 1
    struct Funding {
        uint256 recordedMoneyMarketIncomeIndex; // the income index at the last update (creation or withdrawal)
        uint256 principalPerToken; // The amount of stablecoins that's earning interest for you per funding token you own. Scaled to 18 decimals regardless of stablecoin decimals.
        uint64 depositID; // The ID of the associated Deposit struct.
    }
    Funding[] internal fundingList;
    // the sum of (recordedFundedPrincipalAmount / recordedMoneyMarketIncomeIndex) of all fundings
    uint256 public sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex;

    // Params
    /**
        @dev Maximum deposit period, in seconds
     */
    uint256 public MaxDepositPeriod;
    /**
        @dev Minimum deposit amount, in stablecoins
     */
    uint256 public MinDepositAmount;

    // Global variables
    uint256 public totalDeposit;
    uint256 public totalInterestOwed;
    uint256 public totalFeeOwed;
    uint256 public totalFundedPrincipalAmount;

    // External smart contracts
    IMoneyMarket public moneyMarket;
    ERC20Upgradeable public stablecoin;
    IFeeModel public feeModel;
    IInterestModel public interestModel;
    IInterestOracle public interestOracle;
    NFT public depositNFT;
    FundingMultitoken public fundingMultitoken;
    MPHMinter public mphMinter;

    // Events
    event EDeposit(
        address indexed sender,
        uint64 indexed depositID,
        uint256 depositAmount,
        uint256 interestAmount,
        uint256 feeAmount,
        uint64 maturationTimestamp
    );
    event ETopupDeposit(
        address indexed sender,
        uint64 indexed depositID,
        uint256 depositAmount,
        uint256 interestAmount,
        uint256 feeAmount
    );
    event ERolloverDeposit(
        address indexed sender,
        uint64 indexed depositID,
        uint64 indexed newDepositID
    );
    event EWithdraw(
        address indexed sender,
        uint64 indexed depositID,
        uint256 tokenAmount,
        uint256 feeAmount
    );
    event EFund(
        address indexed sender,
        uint64 indexed fundingID,
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

    function __DInterest_init(
        uint256 _MaxDepositPeriod,
        uint256 _MinDepositAmount,
        address _moneyMarket,
        address _stablecoin,
        address _feeModel,
        address _interestModel,
        address _interestOracle,
        address _depositNFT,
        address _fundingMultitoken,
        address _mphMinter
    ) internal initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        __DInterest_init_unchained(
            _MaxDepositPeriod,
            _MinDepositAmount,
            _moneyMarket,
            _stablecoin,
            _feeModel,
            _interestModel,
            _interestOracle,
            _depositNFT,
            _fundingMultitoken,
            _mphMinter
        );
    }

    function __DInterest_init_unchained(
        uint256 _MaxDepositPeriod,
        uint256 _MinDepositAmount,
        address _moneyMarket,
        address _stablecoin,
        address _feeModel,
        address _interestModel,
        address _interestOracle,
        address _depositNFT,
        address _fundingMultitoken,
        address _mphMinter
    ) internal initializer {
        // Verify input addresses
        require(
            _moneyMarket.isContract() &&
                _stablecoin.isContract() &&
                _feeModel.isContract() &&
                _interestModel.isContract() &&
                _interestOracle.isContract() &&
                _depositNFT.isContract() &&
                _fundingMultitoken.isContract() &&
                _mphMinter.isContract(),
            "DInterest: An input address is not a contract"
        );

        moneyMarket = IMoneyMarket(_moneyMarket);
        stablecoin = ERC20Upgradeable(_stablecoin);
        feeModel = IFeeModel(_feeModel);
        interestModel = IInterestModel(_interestModel);
        interestOracle = IInterestOracle(_interestOracle);
        depositNFT = NFT(_depositNFT);
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
        @param _MaxDepositPeriod The maximum deposit period, in seconds
        @param _MinDepositAmount The minimum deposit amount, in stablecoins
        @param _moneyMarket Address of IMoneyMarket that's used for generating interest (owner must be set to this DInterest contract)
        @param _stablecoin Address of the stablecoin used to store funds
        @param _feeModel Address of the FeeModel contract that determines how fees are charged
        @param _interestModel Address of the InterestModel contract that determines how much interest to offer
        @param _interestOracle Address of the InterestOracle contract that provides the average interest rate
        @param _depositNFT Address of the NFT representing ownership of deposits (owner must be set to this DInterest contract)
        @param _fundingMultitoken Address of the ERC1155 multitoken representing ownership of fundings (this DInterest contract must have the minter-burner role)
        @param _mphMinter Address of the contract for handling minting MPH to users
     */
    function initialize(
        uint256 _MaxDepositPeriod,
        uint256 _MinDepositAmount,
        address _moneyMarket,
        address _stablecoin,
        address _feeModel,
        address _interestModel,
        address _interestOracle,
        address _depositNFT,
        address _fundingMultitoken,
        address _mphMinter
    ) external virtual initializer {
        __DInterest_init(
            _MaxDepositPeriod,
            _MinDepositAmount,
            _moneyMarket,
            _stablecoin,
            _feeModel,
            _interestModel,
            _interestOracle,
            _depositNFT,
            _fundingMultitoken,
            _mphMinter
        );
    }

    /**
        Public action functions
     */

    /**
        @notice Create a deposit using `depositAmount` stablecoin that matures at timestamp `maturationTimestamp`.
        @dev The ERC-721 NFT representing deposit ownership is given to msg.sender
        @param depositAmount The amount of deposit, in stablecoin
        @param maturationTimestamp The Unix timestamp of maturation, in seconds
        @return depositID The ID of the created deposit
        @return interestAmount The amount of fixed-rate interest
     */
    function deposit(uint256 depositAmount, uint64 maturationTimestamp)
        external
        nonReentrant
        returns (uint64 depositID, uint256 interestAmount)
    {
        return _deposit(depositAmount, maturationTimestamp, false);
    }

    /**
        @notice Add `depositAmount` stablecoin to the existing deposit with ID `depositID`.
        @dev The interest rate for the topped up funds will be the current oracle rate.
        @param depositID The deposit to top up
        @param depositAmount The amount to top up, in stablecoin
        @return interestAmount The amount of interest that will be earned by the topped up funds at maturation
     */
    function topupDeposit(uint64 depositID, uint256 depositAmount)
        external
        nonReentrant
        returns (uint256 interestAmount)
    {
        return _topupDeposit(depositID, depositAmount);
    }

    /**
        @notice Withdraw all funds from deposit with ID `depositID` and use them
                to create a new deposit that matures at time `maturationTimestamp`
        @param depositID The deposit to roll over
        @param maturationTimestamp The Unix timestamp of the new deposit, in seconds
        @return newDepositID The ID of the new deposit
     */
    function rolloverDeposit(uint64 depositID, uint64 maturationTimestamp)
        external
        nonReentrant
        returns (uint64 newDepositID, uint256 interestAmount)
    {
        return _rolloverDeposit(depositID, maturationTimestamp);
    }

    /**
        @notice Withdraws funds from the deposit with ID `depositID`.
        @dev Virtual tokens behave like zero coupon bonds, after maturation withdrawing 1 virtual token
             yields 1 stablecoin. The total supply is given by deposit.virtualTokenTotalSupply
        @param depositID the deposit to withdraw from
        @param virtualTokenAmount the amount of virtual tokens to withdraw
        @param early True if intend to withdraw before maturation, false otherwise
        @return withdrawnStablecoinAmount the amount of stablecoins withdrawn
     */
    function withdraw(
        uint64 depositID,
        uint256 virtualTokenAmount,
        bool early
    ) external nonReentrant returns (uint256 withdrawnStablecoinAmount) {
        return _withdraw(depositID, virtualTokenAmount, early, false);
    }

    /**
        @notice Funds the fixed-rate interest of the deposit with ID `depositID`.
                In exchange, the funder receives the future floating-rate interest
                generated by the portion of the deposit whose interest was funded.
        @dev The sender receives ERC-1155 multitokens (fundingMultitoken) representing
             their floating-rate bonds.
        @param depositID The deposit whose fixed-rate interest will be funded
        @param fundAmount The amount of fixed-rate interest to fund.
                          If it exceeds surplusOfDeposit(depositID), it will be set to
                          the surplus value instead.
        @param fundingID The ID of the fundingMultitoken the sender received
     */
    function fund(uint64 depositID, uint256 fundAmount)
        external
        nonReentrant
        returns (uint64 fundingID)
    {
        return _fund(depositID, fundAmount);
    }

    /**
        @notice Distributes the floating-rate interest accrued by a deposit to the
                floating-rate bond holders.
        @param fundingID The ID of the floating-rate bond
        @return interestAmount The amount of interest distributed, in stablecoins
     */
    function payInterestToFunders(uint64 fundingID)
        external
        returns (uint256 interestAmount)
    {
        return _payInterestToFunders(fundingID);
    }

    /**
        @notice Create multiple deposits. See {deposit} for details.
     */
    function multiDeposit(
        uint256[] calldata depositAmountList,
        uint64[] calldata maturationTimestampList
    )
        external
        nonReentrant
        returns (
            uint64[] memory depositIDList,
            uint256[] memory interestAmountList
        )
    {
        require(
            depositAmountList.length == maturationTimestampList.length,
            "DInterest: List lengths unequal"
        );
        depositIDList = new uint64[](depositAmountList.length);
        interestAmountList = new uint256[](depositAmountList.length);
        for (uint256 i = 0; i < depositAmountList.length; i++) {
            (depositIDList[i], interestAmountList[i]) = _deposit(
                depositAmountList[i],
                maturationTimestampList[i],
                false
            );
        }
    }

    /**
        @notice Tops up multiple deposits. See {topupDeposit} for details.
     */
    function multiTopupDeposit(
        uint64[] calldata depositIDList,
        uint256[] calldata depositAmountList
    ) external nonReentrant returns (uint256[] memory interestAmountList) {
        require(
            depositIDList.length == depositAmountList.length,
            "DInterest: List lengths unequal"
        );
        interestAmountList = new uint256[](depositIDList.length);
        for (uint256 i = 0; i < depositIDList.length; i++) {
            interestAmountList[i] = _topupDeposit(
                depositIDList[i],
                depositAmountList[i]
            );
        }
    }

    /**
        @notice Rolls over multiple deposits. See {rollover} for details.
     */
    function multiRolloverDeposit(
        uint64[] calldata depositIDList,
        uint64[] calldata maturationTimestampList
    )
        external
        nonReentrant
        returns (
            uint64[] memory newDepositIDList,
            uint256[] memory interestAmountList
        )
    {
        require(
            depositIDList.length == maturationTimestampList.length,
            "DInterest: List lengths unequal"
        );
        newDepositIDList = new uint64[](depositIDList.length);
        interestAmountList = new uint256[](depositIDList.length);
        for (uint256 i = 0; i < depositIDList.length; i++) {
            (newDepositIDList[i], interestAmountList[i]) = _rolloverDeposit(
                depositIDList[i],
                maturationTimestampList[i]
            );
        }
    }

    /**
        @notice Withdraws multiple deposits. See {withdraw} for details.
     */
    function multiWithdraw(
        uint64[] calldata depositIDList,
        uint256[] calldata virtualTokenAmountList,
        bool[] calldata earlyList
    )
        external
        nonReentrant
        returns (uint256[] memory withdrawnStablecoinAmountList)
    {
        require(
            depositIDList.length == virtualTokenAmountList.length &&
                depositIDList.length == earlyList.length,
            "DInterest: List lengths unequal"
        );
        withdrawnStablecoinAmountList = new uint256[](depositIDList.length);
        for (uint256 i = 0; i < depositIDList.length; i++) {
            withdrawnStablecoinAmountList[i] = _withdraw(
                depositIDList[i],
                virtualTokenAmountList[i],
                earlyList[i],
                false
            );
        }
    }

    /**
        @notice Mints floating-rate bonds for multiple deposits. See {fund} for details.
     */
    function multiFund(
        uint64[] calldata depositIDList,
        uint256[] calldata fundAmountList
    ) external nonReentrant returns (uint256[] memory fundingIDList) {
        require(
            depositIDList.length == fundAmountList.length,
            "DInterest: List lengths unequal"
        );
        fundingIDList = new uint256[](depositIDList.length);
        for (uint256 i = 0; i < depositIDList.length; i++) {
            fundingIDList[i] = _fund(depositIDList[i], fundAmountList[i]);
        }
    }

    /**
        @notice Triggers interest payout for multiple floating-rate bonds.
                See {payInterestToFunders} for details.
     */
    function multiPayInterestToFunders(uint64[] calldata fundingIDList)
        external
        nonReentrant
        returns (uint256[] memory interestAmountList)
    {
        interestAmountList = new uint256[](fundingIDList.length);
        for (uint256 i = 0; i < fundingIDList.length; i++) {
            interestAmountList[i] = _payInterestToFunders(fundingIDList[i]);
        }
    }

    /**
        Public getter functions
     */

    /**
        @notice Computes the amount of fixed-rate interest (before fees) that
                will be given to a deposit of `depositAmount` stablecoins that
                matures in `depositPeriodInSeconds` seconds.
        @param depositAmount The deposit amount, in stablecoins
        @param depositPeriodInSeconds The deposit period, in seconds
        @return interestAmount The amount of fixed-rate interest (before fees)
     */
    function calculateInterestAmount(
        uint256 depositAmount,
        uint64 depositPeriodInSeconds
    ) public virtual returns (uint256 interestAmount) {
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
        @return interestOwed The floating-rate interest accrued to all floating-rate bond holders
     */
    function totalInterestOwedToFunders()
        public
        virtual
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

    /**
        @notice Computes the pool's overall surplus, which is the value of its holdings
                in the `moneyMarket` minus the amount owed to depositors, funders, and
                the fee beneficiary.
        @return isNegative True if the surplus is negative, false otherwise
        @return surplusAmount The absolute value of the surplus, in stablecoins
     */
    function surplus()
        public
        virtual
        returns (bool isNegative, uint256 surplusAmount)
    {
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

    /**
        @notice Computes the raw surplus of a deposit, which is the current value of the
                deposit in the money market minus the amount owed (deposit + interest + fee).
                The deposit's funding status is not considered here, meaning even if a deposit's
                fixed-rate interest is fully funded, it likely will still have a non-zero surplus.
        @param depositID The ID of the deposit
        @return isNegative True if the surplus is negative, false otherwise
        @return surplusAmount The absolute value of the surplus, in stablecoins
     */
    function rawSurplusOfDeposit(uint64 depositID)
        public
        virtual
        returns (bool isNegative, uint256 surplusAmount)
    {
        Deposit storage depositEntry = _getDeposit(depositID);
        uint256 currentMoneyMarketIncomeIndex = moneyMarket.incomeIndex();
        uint256 depositTokenTotalSupply = depositEntry.virtualTokenTotalSupply;
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

    /**
        @notice Computes the surplus of a deposit, which is the raw surplus of the
                unfunded part of the deposit. If the deposit is not funded, this will
                return the same value as {rawSurplusOfDeposit}.
        @param depositID The ID of the deposit
        @return isNegative True if the surplus is negative, false otherwise
        @return surplusAmount The absolute value of the surplus, in stablecoins
     */
    function surplusOfDeposit(uint64 depositID)
        public
        virtual
        returns (bool isNegative, uint256 surplusAmount)
    {
        (isNegative, surplusAmount) = rawSurplusOfDeposit(depositID);

        uint64 fundingID = _getDeposit(depositID).fundingID;
        if (fundingID != 0) {
            uint256 totalPrincipal =
                _depositVirtualTokenToPrincipal(
                    depositID,
                    _getDeposit(depositID).virtualTokenTotalSupply
                );
            uint256 principalPerToken =
                _getFunding(fundingID).principalPerToken;
            uint256 unfundedPrincipalAmount =
                totalPrincipal -
                    (fundingMultitoken.totalSupply(fundingID) *
                        principalPerToken) /
                    ULTRA_PRECISION;
            surplusAmount =
                (surplusAmount * unfundedPrincipalAmount) /
                totalPrincipal;
        }
    }

    /**
        @notice Computes the amount of stablecoins that can be withdrawn
                by burning `virtualTokenAmount` virtual tokens from the deposit
                with ID `depositID` at time `timestamp`.
        @dev The queried timestamp should >= the deposit's lastTopupTimestamp, since
             the information before this time is forgotten.
        @param depositID The ID of the deposit
        @param virtualTokenAmount The amount of virtual tokens to burn
        @param timestamp The Unix timestamp to query, in seconds
        @return withdrawableAmount The amount of stablecoins (after fee) that can be withdrawn
        @return feeAmount The amount of fees that will be given to the beneficiary
     */
    function withdrawableAmountOfDeposit(
        uint64 depositID,
        uint256 virtualTokenAmount,
        uint256 timestamp
    ) external view returns (uint256 withdrawableAmount, uint256 feeAmount) {
        // Verify input
        Deposit memory depositEntry = _getDeposit(depositID);
        if (
            virtualTokenAmount == 0 ||
            timestamp <= depositEntry.depositTimestamp
        ) {
            return (0, 0);
        }

        // Compute token amounts
        uint256 depositAmount =
            virtualTokenAmount.decdiv(depositEntry.interestRate + PRECISION);
        uint256 interestAmount =
            timestamp >= depositEntry.maturationTimestamp
                ? virtualTokenAmount - depositAmount
                : 0;
        feeAmount = interestAmount.decmul(depositEntry.feeRate);
        withdrawableAmount = depositAmount + interestAmount;
    }

    /**
        @notice Computes the floating-rate interest accrued in the floating-rate
                bond with ID `fundingID`.
        @param fundingID The ID of the floating-rate bond
        @return The interest accrued, in stablecoins
     */
    function accruedInterestOfFunding(uint64 fundingID)
        external
        returns (uint256)
    {
        return _accruedInterestOfFunding(fundingID);
    }

    /**
        @notice Returns the total number of deposits.
        @return deposits.length
     */
    function depositsLength() external view returns (uint256) {
        return deposits.length;
    }

    /**
        @notice Returns the total number of floating-rate bonds.
        @return fundingList.length
     */
    function fundingListLength() external view returns (uint256) {
        return fundingList.length;
    }

    /**
        @notice Returns the Deposit struct associated with the deposit with ID
                `depositID`.
        @param depositID The ID of the deposit
        @return The deposit struct
     */
    function getDeposit(uint64 depositID)
        external
        view
        returns (Deposit memory)
    {
        return deposits[depositID - 1];
    }

    /**
        @notice Returns the Funding struct associated with the floating-rate bond with ID
                `fundingID`.
        @param fundingID The ID of the floating-rate bond
        @return The Funding struct
     */
    function getFunding(uint64 fundingID)
        external
        view
        returns (Funding memory)
    {
        return fundingList[fundingID - 1];
    }

    /**
        @notice A floating-rate bond is no longer active if its principalPerToken becomes 0,
                which occurs when the corresponding deposit is completely withdrawn. When
                such a deposit is topped up, a new Funding struct and floating-rate bond will
                be created.
        @param fundingID The ID of the floating-rate bond
        @return True if the funding is active, false otherwise
     */
    function fundingIsActive(uint64 fundingID) external view returns (bool) {
        return _fundingIsActive(fundingID);
    }

    /**
        @notice Returns the income index of the money market. The income index is
                a non-decreasing value that can be used to determine the amount of
                interest earned during a period.
        @return The income index
     */
    function moneyMarketIncomeIndex() external returns (uint256) {
        return moneyMarket.incomeIndex();
    }

    /**
        Internal action functions
     */

    /**
        @dev See {deposit}
     */
    function _deposit(
        uint256 depositAmount,
        uint64 maturationTimestamp,
        bool rollover
    ) internal virtual returns (uint64 depositID, uint256 interestAmount) {
        (depositID, interestAmount) = _depositRecordData(
            depositAmount,
            maturationTimestamp
        );
        _depositTransferFunds(depositAmount, rollover);
    }

    function _depositRecordData(
        uint256 depositAmount,
        uint64 maturationTimestamp
    ) internal virtual returns (uint64 depositID, uint256 interestAmount) {
        // Ensure input is valid
        require(
            depositAmount >= MinDepositAmount,
            "DInterest: Deposit amount too small"
        );
        uint64 depositPeriod = maturationTimestamp - uint64(block.timestamp);
        require(
            depositPeriod <= MaxDepositPeriod,
            "DInterest: Deposit period too long"
        );

        // Calculate interest
        interestAmount = calculateInterestAmount(depositAmount, depositPeriod);
        require(interestAmount > 0, "DInterest: interestAmount == 0");

        // Calculate fee
        depositID = uint64(deposits.length) + 1;
        uint256 feeAmount =
            feeModel.getInterestFeeAmount(
                address(this),
                depositID,
                interestAmount
            );
        interestAmount -= feeAmount;

        // Record deposit data
        deposits.push(
            Deposit({
                virtualTokenTotalSupply: depositAmount + interestAmount,
                interestRate: interestAmount.decdiv(depositAmount),
                feeRate: feeAmount.decdiv(interestAmount),
                maturationTimestamp: maturationTimestamp,
                depositTimestamp: uint64(block.timestamp),
                fundingID: 0,
                averageRecordedIncomeIndex: moneyMarket.incomeIndex()
            })
        );

        // Update global values
        totalDeposit += depositAmount;
        totalInterestOwed += interestAmount;
        totalFeeOwed += feeAmount;

        // Mint depositNFT
        depositNFT.mint(msg.sender, depositID);

        // Vest MPH to msg.sender
        mphMinter.createVestForDeposit(msg.sender, depositID);

        // Emit event
        emit EDeposit(
            msg.sender,
            depositID,
            depositAmount,
            interestAmount,
            feeAmount,
            maturationTimestamp
        );
    }

    function _depositTransferFunds(uint256 depositAmount, bool rollover)
        internal
        virtual
    {
        // Only transfer funds from sender if it's not a rollover
        // because if it is the funds are already in the contract
        if (!rollover) {
            // Transfer `depositAmount` stablecoin to DInterest
            stablecoin.safeTransferFrom(
                msg.sender,
                address(this),
                depositAmount
            );

            // Lend `depositAmount` stablecoin to money market
            stablecoin.safeIncreaseAllowance(
                address(moneyMarket),
                depositAmount
            );
            moneyMarket.deposit(depositAmount);
        }
    }

    /**
        @dev See {topupDeposit}
     */
    function _topupDeposit(uint64 depositID, uint256 depositAmount)
        internal
        virtual
        returns (uint256 interestAmount)
    {
        interestAmount = _topupDepositRecordData(depositID, depositAmount);
        _topupDepositTransferFunds(depositAmount);
    }

    function _topupDepositRecordData(uint64 depositID, uint256 depositAmount)
        internal
        virtual
        returns (uint256 interestAmount)
    {
        Deposit memory depositEntry = _getDeposit(depositID);
        require(
            depositNFT.ownerOf(depositID) == msg.sender,
            "DInterest: not owner"
        );

        // underflow check prevents topups after maturation
        uint64 depositPeriod =
            depositEntry.maturationTimestamp - uint64(block.timestamp);

        // Calculate interest
        interestAmount = calculateInterestAmount(depositAmount, depositPeriod);
        require(interestAmount > 0, "DInterest: interestAmount == 0");

        // Calculate fee
        uint256 feeAmount =
            feeModel.getInterestFeeAmount(
                address(this),
                depositID,
                interestAmount
            );
        interestAmount -= feeAmount;

        // Update deposit struct
        uint256 currentDepositAmount =
            depositEntry.virtualTokenTotalSupply.decdiv(
                depositEntry.interestRate + PRECISION
            );
        uint256 currentInterestAmount =
            depositEntry.virtualTokenTotalSupply - currentDepositAmount;
        depositEntry.virtualTokenTotalSupply += depositAmount + interestAmount;
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
        uint256 sumOfRecordedDepositAmountDivRecordedIncomeIndex =
            (currentDepositAmount * EXTRA_PRECISION) /
                depositEntry.averageRecordedIncomeIndex +
                (depositAmount * EXTRA_PRECISION) /
                moneyMarket.incomeIndex();
        depositEntry.averageRecordedIncomeIndex =
            ((depositAmount + currentDepositAmount) * EXTRA_PRECISION) /
            sumOfRecordedDepositAmountDivRecordedIncomeIndex;

        deposits[depositID - 1] = depositEntry;

        // Update global values
        totalDeposit += depositAmount;
        totalInterestOwed += interestAmount;
        totalFeeOwed += feeAmount;

        // Update vest
        mphMinter.updateVestForDeposit(
            depositID,
            currentDepositAmount,
            depositAmount
        );

        // Emit event
        emit ETopupDeposit(
            msg.sender,
            depositID,
            depositAmount,
            interestAmount,
            feeAmount
        );
    }

    function _topupDepositTransferFunds(uint256 depositAmount)
        internal
        virtual
    {
        // Transfer `depositAmount` stablecoin to DInterest
        stablecoin.safeTransferFrom(msg.sender, address(this), depositAmount);

        // Lend `depositAmount` stablecoin to money market
        stablecoin.safeIncreaseAllowance(address(moneyMarket), depositAmount);
        moneyMarket.deposit(depositAmount);
    }

    /**
        @dev See {rolloverDeposit}
     */
    function _rolloverDeposit(uint64 depositID, uint64 maturationTimestamp)
        internal
        virtual
        returns (uint64 newDepositID, uint256 interestAmount)
    {
        // withdraw from existing deposit
        uint256 withdrawnStablecoinAmount =
            _withdraw(depositID, type(uint256).max, false, true);

        // deposit funds into a new deposit
        (newDepositID, interestAmount) = _deposit(
            withdrawnStablecoinAmount,
            maturationTimestamp,
            true
        );

        emit ERolloverDeposit(msg.sender, depositID, newDepositID);
    }

    /**
        @dev See {withdraw}
        @param rollover True if being called from {_rolloverDeposit}, false otherwise
     */
    function _withdraw(
        uint64 depositID,
        uint256 virtualTokenAmount,
        bool early,
        bool rollover
    ) internal virtual returns (uint256 withdrawnStablecoinAmount) {
        (
            uint256 withdrawAmount,
            uint256 feeAmount,
            uint256 fundingInterestAmount,
            uint256 refundAmount
        ) = _withdrawRecordData(depositID, virtualTokenAmount, early);
        return
            _withdrawTransferFunds(
                _getDeposit(depositID).fundingID,
                withdrawAmount,
                feeAmount,
                fundingInterestAmount,
                refundAmount,
                rollover
            );
    }

    function _withdrawRecordData(
        uint64 depositID,
        uint256 virtualTokenAmount,
        bool early
    )
        internal
        virtual
        returns (
            uint256 withdrawAmount,
            uint256 feeAmount,
            uint256 fundingInterestAmount,
            uint256 refundAmount
        )
    {
        // Verify input
        require(virtualTokenAmount > 0, "DInterest: 0 amount");
        Deposit memory depositEntry = _getDeposit(depositID);
        require(
            block.timestamp > depositEntry.depositTimestamp,
            "DInterest: Deposited in same block"
        );
        if (early) {
            require(
                block.timestamp < depositEntry.maturationTimestamp,
                "DInterest: mature"
            );
        } else {
            require(
                block.timestamp >= depositEntry.maturationTimestamp,
                "DInterest: immature"
            );
        }

        // Check if withdrawing all funds
        if (virtualTokenAmount == type(uint256).max) {
            virtualTokenAmount = depositEntry.virtualTokenTotalSupply;
        }

        // Compute token amounts
        uint256 depositAmount =
            virtualTokenAmount.decdiv(depositEntry.interestRate + PRECISION);
        {
            uint256 interestAmount =
                early ? 0 : virtualTokenAmount - depositAmount;
            withdrawAmount = depositAmount + interestAmount;
            feeAmount = interestAmount.decmul(depositEntry.feeRate);
        }

        if (early) {
            // apply fee to withdrawAmount
            uint256 earlyWithdrawFee =
                feeModel.getEarlyWithdrawFeeAmount(
                    address(this),
                    depositID,
                    withdrawAmount
                );
            feeAmount += earlyWithdrawFee;
            withdrawAmount -= earlyWithdrawFee;
        }

        // Update global values
        totalDeposit -= depositAmount;
        totalInterestOwed -= virtualTokenAmount - depositAmount;
        totalFeeOwed -= (virtualTokenAmount - depositAmount).decmul(
            depositEntry.feeRate
        );

        // If deposit was funded, compute funding interest payout
        if (depositEntry.fundingID > 0) {
            Funding storage funding = _getFunding(depositEntry.fundingID);

            // Compute funded deposit amount before withdrawal
            uint256 fundingTokenTotalSupply =
                fundingMultitoken.totalSupply(depositEntry.fundingID);
            uint256 recordedFundedPrincipalAmount =
                (fundingTokenTotalSupply * funding.principalPerToken) /
                    ULTRA_PRECISION;
            uint256 totalPrincipal =
                _depositVirtualTokenToPrincipal(
                    depositID,
                    depositEntry.virtualTokenTotalSupply
                );

            // Shrink funding principal per token value
            uint256 totalPrincipalDecrease =
                virtualTokenAmount +
                    (virtualTokenAmount - depositAmount).decmul(
                        depositEntry.feeRate
                    );
            if (
                totalPrincipal <=
                totalPrincipalDecrease + recordedFundedPrincipalAmount
            ) {
                // Not enough unfunded principal, need to decrease funding principal per token value
                funding.principalPerToken =
                    (funding.principalPerToken *
                        (totalPrincipal - totalPrincipalDecrease)) /
                    recordedFundedPrincipalAmount;
            }

            // Compute interest payout + refund
            // and update relevant state
            (
                fundingInterestAmount,
                refundAmount
            ) = _computeAndUpdateFundingInterestAfterWithdraw(
                depositEntry.fundingID,
                recordedFundedPrincipalAmount,
                early
            );
        }

        // Burn `virtualTokenAmount` deposit virtual tokens
        _getDeposit(depositID).virtualTokenTotalSupply -= virtualTokenAmount;

        // Emit event
        emit EWithdraw(msg.sender, depositID, virtualTokenAmount, feeAmount);
    }

    function _withdrawTransferFunds(
        uint64 fundingID,
        uint256 withdrawAmount,
        uint256 feeAmount,
        uint256 fundingInterestAmount,
        uint256 refundAmount,
        bool rollover
    ) internal virtual returns (uint256 withdrawnStablecoinAmount) {
        // Withdraw funds from money market
        // Withdraws principal together with funding interest to save gas
        if (rollover) {
            // Rollover mode, don't withdraw `withdrawAmount` from moneyMarket

            // We do this because feePlusFundingInterest might
            // be slightly less due to rounding
            uint256 feePlusFundingInterest =
                moneyMarket.withdraw(feeAmount + fundingInterestAmount);
            if (feePlusFundingInterest >= feeAmount + fundingInterestAmount) {
                // enough to pay everything, if there's extra give to feeAmount
                feeAmount = feePlusFundingInterest - fundingInterestAmount;
            } else if (feePlusFundingInterest >= feeAmount) {
                // enough to pay fee, give remainder to fundingInterestAmount
                fundingInterestAmount = feePlusFundingInterest - feeAmount;
            } else {
                // not enough to pay fee, give everything to fee
                feeAmount = feePlusFundingInterest;
                fundingInterestAmount = 0;
            }

            // we're keeping the withdrawal amount in the money market
            withdrawnStablecoinAmount = withdrawAmount;
        } else {
            uint256 actualWithdrawnAmount =
                moneyMarket.withdraw(
                    withdrawAmount + feeAmount + fundingInterestAmount
                );

            // We do this because `actualWithdrawnAmount` might
            // be slightly less due to rounding
            withdrawnStablecoinAmount = withdrawAmount;
            if (
                actualWithdrawnAmount >=
                withdrawAmount + feeAmount + fundingInterestAmount
            ) {
                // enough to pay everything, if there's extra give to feeAmount
                feeAmount =
                    actualWithdrawnAmount -
                    withdrawAmount -
                    fundingInterestAmount;
            } else if (actualWithdrawnAmount >= withdrawAmount + feeAmount) {
                // enough to pay withdrawal + fee + remainder
                // give remainder to funding interest
                fundingInterestAmount =
                    actualWithdrawnAmount -
                    withdrawAmount -
                    feeAmount;
            } else if (actualWithdrawnAmount >= withdrawAmount) {
                // enough to pay withdrawal + remainder
                // give remainder to fee
                feeAmount = actualWithdrawnAmount - withdrawAmount;
            } else {
                // not enough to pay withdrawal
                // give everything to withdrawal
                withdrawnStablecoinAmount = actualWithdrawnAmount;
            }

            if (withdrawnStablecoinAmount > 0) {
                stablecoin.safeTransfer(msg.sender, withdrawnStablecoinAmount);
            }
        }

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
                fundingID,
                address(stablecoin),
                fundingInterestAmount
            );
            // Mint funder rewards
            if (fundingInterestAmount >= refundAmount) {
                mphMinter.distributeFundingRewards(
                    fundingID,
                    fundingInterestAmount - refundAmount
                );
            }
        }
    }

    /**
        @dev See {fund}
     */
    function _fund(uint64 depositID, uint256 fundAmount)
        internal
        virtual
        returns (uint64 fundingID)
    {
        uint256 actualFundAmount;
        (fundingID, actualFundAmount) = _fundRecordData(depositID, fundAmount);
        _fundTransferFunds(actualFundAmount);
    }

    function _fundRecordData(uint64 depositID, uint256 fundAmount)
        internal
        virtual
        returns (uint64 fundingID, uint256 actualFundAmount)
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
            _depositVirtualTokenToPrincipal(
                depositID,
                depositEntry.virtualTokenTotalSupply
            );
        uint256 totalPrincipalToFund;
        fundingID = depositEntry.fundingID;
        uint256 mintTokenAmount;
        if (fundingID == 0 || _getFunding(fundingID).principalPerToken == 0) {
            // The first funder, create struct
            fundingList.push(
                Funding({
                    depositID: depositID,
                    recordedMoneyMarketIncomeIndex: incomeIndex,
                    principalPerToken: ULTRA_PRECISION
                })
            );
            fundingID = uint64(fundingList.length);
            depositEntry.fundingID = fundingID;
            totalPrincipalToFund =
                (totalPrincipal * fundAmount) /
                surplusMagnitude;
            mintTokenAmount = totalPrincipalToFund;
        } else {
            // Not the first funder
            // Trigger interest payment for existing funders
            _payInterestToFunders(fundingID);

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

        // Emit event
        emit EFund(msg.sender, fundingID, fundAmount, mintTokenAmount);

        actualFundAmount = fundAmount;
    }

    function _fundTransferFunds(uint256 fundAmount) internal virtual {
        // Transfer `fundAmount` stablecoins from msg.sender
        stablecoin.safeTransferFrom(msg.sender, address(this), fundAmount);

        // Deposit `fundAmount` stablecoins into moneyMarket
        stablecoin.safeIncreaseAllowance(address(moneyMarket), fundAmount);
        moneyMarket.deposit(fundAmount);
    }

    /**
        @dev See {payInterestToFunders}
     */
    function _payInterestToFunders(uint64 fundingID)
        internal
        virtual
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
                    address(stablecoin),
                    interestAmount
                );

                // Mint funder rewards
                mphMinter.distributeFundingRewards(fundingID, interestAmount);
            }
        }
    }

    /**
        @dev Used in {_withdraw}. Computes the amount of interest to distribute
             to the deposit's floating-rate bond holders. Also updates the Funding
             struct associated with the floating-rate bond.
        @param fundingID The ID of the floating-rate bond
        @param recordedFundedPrincipalAmount The amount of principal funded before the withdrawal
        @param early True if withdrawing before maturation, false otherwise
        @return fundingInterestAmount The amount of interest to distribute to the floating-rate bond holders, plus the refund amount
        @return refundAmount The amount of refund caused by an early withdraw
     */
    function _computeAndUpdateFundingInterestAfterWithdraw(
        uint64 fundingID,
        uint256 recordedFundedPrincipalAmount,
        bool early
    )
        internal
        virtual
        returns (uint256 fundingInterestAmount, uint256 refundAmount)
    {
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
        {
            uint256 currentFundedPrincipalAmountDivRecordedIncomeIndex =
                (currentFundedPrincipalAmount * EXTRA_PRECISION) /
                    currentMoneyMarketIncomeIndex;
            uint256 recordedFundedPrincipalAmountDivRecordedIncomeIndex =
                (recordedFundedPrincipalAmount * EXTRA_PRECISION) /
                    recordedMoneyMarketIncomeIndex;
            if (
                sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex +
                    currentFundedPrincipalAmountDivRecordedIncomeIndex >=
                recordedFundedPrincipalAmountDivRecordedIncomeIndex
            ) {
                sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex =
                    sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex +
                    currentFundedPrincipalAmountDivRecordedIncomeIndex -
                    recordedFundedPrincipalAmountDivRecordedIncomeIndex;
            } else {
                sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex = 0;
            }
        }

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
        if (early) {
            Deposit memory depositEntry = _getDeposit(f.depositID);
            (, uint256 moneyMarketInterestRatePerSecond) =
                interestOracle.updateAndQuery();
            refundAmount =
                (((recordedFundedPrincipalAmount -
                    currentFundedPrincipalAmount) * PRECISION)
                    .decmul(moneyMarketInterestRatePerSecond) *
                    (depositEntry.maturationTimestamp - block.timestamp)) /
                PRECISION;
            uint256 maxRefundAmount =
                (recordedFundedPrincipalAmount - currentFundedPrincipalAmount)
                    .decdiv(
                    PRECISION +
                        depositEntry.interestRate +
                        depositEntry.interestRate.decmul(depositEntry.feeRate)
                )
                    .decmul(
                    depositEntry.interestRate +
                        depositEntry.interestRate.decmul(depositEntry.feeRate)
                );
            refundAmount = MathUpgradeable.min(refundAmount, maxRefundAmount);
            fundingInterestAmount += refundAmount;
        }
    }

    /**
        Internal getter functions
     */

    /**
        @dev See {getDeposit}
     */
    function _getDeposit(uint64 depositID)
        internal
        view
        returns (Deposit storage)
    {
        return deposits[depositID - 1];
    }

    /**
        @dev See {getFunding}
     */
    function _getFunding(uint64 fundingID)
        internal
        view
        returns (Funding storage)
    {
        return fundingList[fundingID - 1];
    }

    /**
        @dev See {fundingIsActive}
     */
    function _fundingIsActive(uint64 fundingID) internal view returns (bool) {
        return _getFunding(fundingID).principalPerToken > 0;
    }

    /**
        @dev Converts a virtual token value into the corresponding principal value.
             Principal refers to deposit + full interest + fee.
        @param depositID The ID of the deposit of the virtual tokens
        @param virtualTokenAmount The virtual token value
        @return The corresponding principal value
     */
    function _depositVirtualTokenToPrincipal(
        uint64 depositID,
        uint256 virtualTokenAmount
    ) internal view virtual returns (uint256) {
        Deposit storage depositEntry = _getDeposit(depositID);
        uint256 depositInterestRate = depositEntry.interestRate;
        return
            virtualTokenAmount.decdiv(depositInterestRate + PRECISION).decmul(
                depositInterestRate +
                    depositInterestRate.decmul(depositEntry.feeRate) +
                    PRECISION
            );
    }

    /**
        @dev See {accruedInterestOfFunding}
     */
    function _accruedInterestOfFunding(uint64 fundingID)
        internal
        virtual
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

    /**
        Param setters (only callable by the owner)
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

    function setDepositNFTBaseURI(string calldata newURI) external onlyOwner {
        depositNFT.setBaseURI(newURI);
    }

    function setDepositNFTContractURI(string calldata newURI)
        external
        onlyOwner
    {
        depositNFT.setContractURI(newURI);
    }
}
