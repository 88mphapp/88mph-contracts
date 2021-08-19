// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "./libs/SafeERC20.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {
    AddressUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {BoringOwnable} from "./libs/BoringOwnable.sol";
import {
    MulticallUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {MoneyMarket} from "./moneymarkets/MoneyMarket.sol";
import {IFeeModel} from "./models/fee/IFeeModel.sol";
import {IInterestModel} from "./models/interest/IInterestModel.sol";
import {NFT} from "./tokens/NFT.sol";
import {FundingMultitoken} from "./tokens/FundingMultitoken.sol";
import {MPHMinter} from "./rewards/MPHMinter.sol";
import {IInterestOracle} from "./models/interest-oracle/IInterestOracle.sol";
import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";
import {Rescuable} from "./libs/Rescuable.sol";
import {console} from "hardhat/console.sol";

/**
    @title DeLorean Interest -- It's coming back from the future!
    @author Zefram Lou
    @notice The main pool contract for fixed-rate deposits
    @dev The contract to interact with for most actions
 */
contract DInterest is
    ReentrancyGuardUpgradeable,
    BoringOwnable,
    Rescuable,
    MulticallUpgradeable
{
    using SafeERC20 for ERC20;
    using AddressUpgradeable for address;
    using PRBMathUD60x18 for uint256;

    // Constants
    uint256 internal constant PRECISION = 10**18;
    /**
        @dev used for sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex
     */
    uint256 internal constant EXTRA_PRECISION = 10**27;
    /**
        @dev used for funding.principalPerToken
     */
    uint256 internal constant ULTRA_PRECISION = 2**128;
    /**
        @dev Specifies the threshold for paying out funder interests
     */
    uint256 internal constant FUNDER_PAYOUT_THRESHOLD_DIVISOR = 10**10;

    // User deposit data
    // Each deposit has an ID used in the depositNFT, which is equal to its index in `deposits` plus 1
    struct Deposit {
        uint256 virtualTokenTotalSupply; // depositAmount + interestAmount, behaves like a zero coupon bond
        uint256 interestRate; // interestAmount = interestRate * depositAmount
        uint256 feeRate; // feeAmount = feeRate * depositAmount
        uint256 averageRecordedIncomeIndex; // Average income index at time of deposit, used for computing deposit surplus
        uint64 maturationTimestamp; // Unix timestamp after which the deposit may be withdrawn, in seconds
        uint64 fundingID; // The ID of the associated Funding struct. 0 if not funded.
    }
    Deposit[] internal deposits;

    // Funding data
    // Each funding has an ID used in the fundingMultitoken, which is equal to its index in `fundingList` plus 1
    struct Funding {
        uint64 depositID; // The ID of the associated Deposit struct.
        uint64 lastInterestPayoutTimestamp; // Unix timestamp of the most recent interest payout, in seconds
        uint256 recordedMoneyMarketIncomeIndex; // the income index at the last update (creation or withdrawal)
        uint256 principalPerToken; // The amount of stablecoins that's earning interest for you per funding token you own. Scaled to 18 decimals regardless of stablecoin decimals.
    }
    Funding[] internal fundingList;
    // the sum of (recordedFundedPrincipalAmount / recordedMoneyMarketIncomeIndex) of all fundings
    uint256 public sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex;

    // Params
    /**
        @dev Maximum deposit period, in seconds
     */
    uint64 public MaxDepositPeriod;
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
    IFeeModel public feeModel;
    IInterestModel public interestModel;
    IInterestOracle public interestOracle;
    NFT public depositNFT;
    FundingMultitoken public fundingMultitoken;
    MPHMinter public mphMinter;

    // Extra params
    /**
        @dev The maximum amount of deposit in the pool. Set to 0 to disable the cap.
     */
    uint256 public GlobalDepositCap;

    // Events
    event EDeposit(
        address indexed sender,
        uint256 indexed depositID,
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
        uint256 indexed depositID,
        bool indexed early,
        uint256 virtualTokenAmount,
        uint256 feeAmount
    );
    event EFund(
        address indexed sender,
        uint64 indexed fundingID,
        uint256 fundAmount,
        uint256 tokenAmount
    );
    event EPayFundingInterest(
        uint256 indexed fundingID,
        uint256 interestAmount,
        uint256 refundAmount
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
        uint64 _MaxDepositPeriod,
        uint256 _MinDepositAmount,
        address _feeModel,
        address _interestModel,
        address _interestOracle,
        address _depositNFT,
        address _fundingMultitoken,
        address _mphMinter
    ) internal initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        feeModel = IFeeModel(_feeModel);
        interestModel = IInterestModel(_interestModel);
        interestOracle = IInterestOracle(_interestOracle);
        depositNFT = NFT(_depositNFT);
        fundingMultitoken = FundingMultitoken(_fundingMultitoken);
        mphMinter = MPHMinter(_mphMinter);
        MaxDepositPeriod = _MaxDepositPeriod;
        MinDepositAmount = _MinDepositAmount;
    }

    /**
        @param _MaxDepositPeriod The maximum deposit period, in seconds
        @param _MinDepositAmount The minimum deposit amount, in stablecoins
        @param _feeModel Address of the FeeModel contract that determines how fees are charged
        @param _interestModel Address of the InterestModel contract that determines how much interest to offer
        @param _interestOracle Address of the InterestOracle contract that provides the average interest rate
        @param _depositNFT Address of the NFT representing ownership of deposits (owner must be set to this DInterest contract)
        @param _fundingMultitoken Address of the ERC1155 multitoken representing ownership of fundings (this DInterest contract must have the minter-burner role)
        @param _mphMinter Address of the contract for handling minting MPH to users
     */
    function initialize(
        uint64 _MaxDepositPeriod,
        uint256 _MinDepositAmount,
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
        return
            _deposit(
                msg.sender,
                depositAmount,
                maturationTimestamp,
                false,
                0,
                ""
            );
    }

    /**
        @notice Create a deposit using `depositAmount` stablecoin that matures at timestamp `maturationTimestamp`.
        @dev The ERC-721 NFT representing deposit ownership is given to msg.sender
        @param depositAmount The amount of deposit, in stablecoin
        @param maturationTimestamp The Unix timestamp of maturation, in seconds
        @param minimumInterestAmount If the interest amount is less than this, revert
        @param uri The metadata URI for the minted NFT
        @return depositID The ID of the created deposit
        @return interestAmount The amount of fixed-rate interest
     */
    function deposit(
        uint256 depositAmount,
        uint64 maturationTimestamp,
        uint256 minimumInterestAmount,
        string calldata uri
    ) external nonReentrant returns (uint64 depositID, uint256 interestAmount) {
        return
            _deposit(
                msg.sender,
                depositAmount,
                maturationTimestamp,
                false,
                minimumInterestAmount,
                uri
            );
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
        return _topupDeposit(msg.sender, depositID, depositAmount, 0);
    }

    /**
        @notice Add `depositAmount` stablecoin to the existing deposit with ID `depositID`.
        @dev The interest rate for the topped up funds will be the current oracle rate.
        @param depositID The deposit to top up
        @param depositAmount The amount to top up, in stablecoin
        @param minimumInterestAmount If the interest amount is less than this, revert
        @return interestAmount The amount of interest that will be earned by the topped up funds at maturation
     */
    function topupDeposit(
        uint64 depositID,
        uint256 depositAmount,
        uint256 minimumInterestAmount
    ) external nonReentrant returns (uint256 interestAmount) {
        return
            _topupDeposit(
                msg.sender,
                depositID,
                depositAmount,
                minimumInterestAmount
            );
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
        returns (uint256 newDepositID, uint256 interestAmount)
    {
        return
            _rolloverDeposit(msg.sender, depositID, maturationTimestamp, 0, "");
    }

    /**
        @notice Withdraw all funds from deposit with ID `depositID` and use them
                to create a new deposit that matures at time `maturationTimestamp`
        @param depositID The deposit to roll over
        @param maturationTimestamp The Unix timestamp of the new deposit, in seconds
        @param minimumInterestAmount If the interest amount is less than this, revert
        @param uri The metadata URI of the NFT
        @return newDepositID The ID of the new deposit
     */
    function rolloverDeposit(
        uint64 depositID,
        uint64 maturationTimestamp,
        uint256 minimumInterestAmount,
        string calldata uri
    )
        external
        nonReentrant
        returns (uint256 newDepositID, uint256 interestAmount)
    {
        return
            _rolloverDeposit(
                msg.sender,
                depositID,
                maturationTimestamp,
                minimumInterestAmount,
                uri
            );
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
        return
            _withdraw(msg.sender, depositID, virtualTokenAmount, early, false);
    }

    /**
        @notice Funds the fixed-rate interest of the deposit with ID `depositID`.
                In exchange, the funder receives the future floating-rate interest
                generated by the portion of the deposit whose interest was funded.
        @dev The sender receives ERC-1155 multitokens (fundingMultitoken) representing
             their funding position.
        @param depositID The deposit whose fixed-rate interest will be funded
        @param fundAmount The amount of stablecoins to pay for the fundingMultitokens.
                          If it exceeds the upper bound, it will be set to
                          the bound value instead. (See {_fund} implementation)
        @return fundingID The ID of the fundingMultitoken the sender received
        @return fundingMultitokensMinted The amount of fundingMultitokens minted to the sender
        @return actualFundAmount The amount of stablecoins paid by the sender
        @return principalFunded The amount of principal the minted fundingMultitokens is earning yield on
     */
    function fund(uint64 depositID, uint256 fundAmount)
        external
        nonReentrant
        returns (
            uint64 fundingID,
            uint256 fundingMultitokensMinted,
            uint256 actualFundAmount,
            uint256 principalFunded
        )
    {
        return _fund(msg.sender, depositID, fundAmount, 0);
    }

    /**
        @notice Funds the fixed-rate interest of the deposit with ID `depositID`.
                In exchange, the funder receives the future floating-rate interest
                generated by the portion of the deposit whose interest was funded.
        @dev The sender receives ERC-1155 multitokens (fundingMultitoken) representing
             their funding position.
        @param depositID The deposit whose fixed-rate interest will be funded
        @param fundAmount The amount of stablecoins to pay for the fundingMultitokens.
                          If it exceeds the upper bound, it will be set to
                          the bound value instead. (See {_fund} implementation)
        @param minPrincipalFunded The minimum amount of principalFunded, below which the tx will revert
        @return fundingID The ID of the fundingMultitoken the sender received
        @return fundingMultitokensMinted The amount of fundingMultitokens minted to the sender
        @return actualFundAmount The amount of stablecoins paid by the sender
        @return principalFunded The amount of principal the minted fundingMultitokens is earning yield on
     */
    function fund(
        uint64 depositID,
        uint256 fundAmount,
        uint256 minPrincipalFunded
    )
        external
        nonReentrant
        returns (
            uint64 fundingID,
            uint256 fundingMultitokensMinted,
            uint256 actualFundAmount,
            uint256 principalFunded
        )
    {
        return _fund(msg.sender, depositID, fundAmount, minPrincipalFunded);
    }

    /**
        @notice Distributes the floating-rate interest accrued by a deposit to the
                floating-rate bond holders.
        @param fundingID The ID of the floating-rate bond
        @return interestAmount The amount of interest distributed, in stablecoins
     */
    function payInterestToFunders(uint64 fundingID)
        external
        nonReentrant
        returns (uint256 interestAmount)
    {
        return _payInterestToFunders(fundingID, moneyMarket().incomeIndex());
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
        uint256 depositPeriodInSeconds
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
        return _surplus(moneyMarket().incomeIndex());
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
        @notice Returns the moneyMarket contract
        @return The moneyMarket
     */
    function moneyMarket() public view returns (MoneyMarket) {
        return interestOracle.moneyMarket();
    }

    /**
        @notice Returns the stablecoin ERC20 token contract
        @return The stablecoin
     */
    function stablecoin() public view returns (ERC20) {
        return moneyMarket().stablecoin();
    }

    /**
        Internal action functions
     */

    /**
        @dev See {deposit}
     */
    function _deposit(
        address sender,
        uint256 depositAmount,
        uint64 maturationTimestamp,
        bool rollover,
        uint256 minimumInterestAmount,
        string memory uri
    ) internal virtual returns (uint64 depositID, uint256 interestAmount) {
        (depositID, interestAmount) = _depositRecordData(
            sender,
            depositAmount,
            maturationTimestamp,
            minimumInterestAmount,
            uri
        );
        _depositTransferFunds(sender, depositAmount, rollover);
    }

    function _depositRecordData(
        address sender,
        uint256 depositAmount,
        uint64 maturationTimestamp,
        uint256 minimumInterestAmount,
        string memory uri
    ) internal virtual returns (uint64 depositID, uint256 interestAmount) {
        // Ensure input is valid
        require(depositAmount >= MinDepositAmount, "BAD_AMOUNT");
        uint256 depositPeriod = maturationTimestamp - block.timestamp;
        require(depositPeriod <= MaxDepositPeriod, "BAD_TIME");

        // Calculate interest
        interestAmount = calculateInterestAmount(depositAmount, depositPeriod);
        require(
            interestAmount > 0 && interestAmount >= minimumInterestAmount,
            "BAD_INTEREST"
        );

        // Calculate fee
        uint256 feeAmount =
            feeModel.getInterestFeeAmount(address(this), interestAmount);
        interestAmount -= feeAmount;

        // Record deposit data
        deposits.push(
            Deposit({
                virtualTokenTotalSupply: depositAmount + interestAmount,
                interestRate: interestAmount.div(depositAmount),
                feeRate: feeAmount.div(depositAmount),
                maturationTimestamp: maturationTimestamp,
                fundingID: 0,
                averageRecordedIncomeIndex: interestOracle
                    .moneyMarket()
                    .incomeIndex()
            })
        );
        require(deposits.length <= type(uint64).max, "OVERFLOW");
        depositID = uint64(deposits.length);

        // Update global values
        totalDeposit += depositAmount;
        {
            uint256 depositCap = GlobalDepositCap;
            require(depositCap == 0 || totalDeposit <= depositCap, "CAP");
        }
        totalInterestOwed += interestAmount;
        totalFeeOwed += feeAmount;

        // Mint depositNFT
        if (bytes(uri).length == 0) {
            depositNFT.mint(sender, depositID);
        } else {
            depositNFT.mint(sender, depositID, uri);
        }

        // Emit event
        emit EDeposit(
            sender,
            depositID,
            depositAmount,
            interestAmount,
            feeAmount,
            maturationTimestamp
        );

        // Vest MPH to sender
        mphMinter.createVestForDeposit(sender, depositID);
    }

    function _depositTransferFunds(
        address sender,
        uint256 depositAmount,
        bool rollover
    ) internal virtual {
        // Only transfer funds from sender if it's not a rollover
        // because if it is the funds are already in the contract
        if (!rollover) {
            ERC20 _stablecoin = stablecoin();

            // Transfer `depositAmount` stablecoin to DInterest
            _stablecoin.safeTransferFrom(sender, address(this), depositAmount);

            // Lend `depositAmount` stablecoin to money market
            MoneyMarket _moneyMarket = moneyMarket();
            _stablecoin.safeIncreaseAllowance(
                address(_moneyMarket),
                depositAmount
            );
            _moneyMarket.deposit(depositAmount);
        }
    }

    /**
        @dev See {topupDeposit}
     */
    function _topupDeposit(
        address sender,
        uint64 depositID,
        uint256 depositAmount,
        uint256 minimumInterestAmount
    ) internal virtual returns (uint256 interestAmount) {
        interestAmount = _topupDepositRecordData(
            sender,
            depositID,
            depositAmount,
            minimumInterestAmount
        );
        _topupDepositTransferFunds(sender, depositAmount);
    }

    function _topupDepositRecordData(
        address sender,
        uint64 depositID,
        uint256 depositAmount,
        uint256 minimumInterestAmount
    ) internal virtual returns (uint256 interestAmount) {
        Deposit storage depositEntry = _getDeposit(depositID);
        require(depositNFT.ownerOf(depositID) == sender, "NOT_OWNER");

        // underflow check prevents topups after maturation
        uint256 depositPeriod =
            depositEntry.maturationTimestamp - block.timestamp;

        // Calculate interest
        interestAmount = calculateInterestAmount(depositAmount, depositPeriod);
        require(
            interestAmount > 0 && interestAmount >= minimumInterestAmount,
            "BAD_INTEREST"
        );

        // Calculate fee
        uint256 feeAmount =
            feeModel.getInterestFeeAmount(address(this), interestAmount);
        interestAmount -= feeAmount;

        // Update deposit struct
        uint256 interestRate = depositEntry.interestRate;
        uint256 currentDepositAmount =
            depositEntry.virtualTokenTotalSupply.div(interestRate + PRECISION);
        depositEntry.virtualTokenTotalSupply += depositAmount + interestAmount;
        depositEntry.interestRate =
            (PRECISION * interestAmount + currentDepositAmount * interestRate) /
            (depositAmount + currentDepositAmount);
        depositEntry.feeRate =
            (PRECISION *
                feeAmount +
                currentDepositAmount *
                depositEntry.feeRate) /
            (depositAmount + currentDepositAmount);
        uint256 sumOfRecordedDepositAmountDivRecordedIncomeIndex =
            (currentDepositAmount * EXTRA_PRECISION) /
                depositEntry.averageRecordedIncomeIndex +
                (depositAmount * EXTRA_PRECISION) /
                moneyMarket().incomeIndex();
        depositEntry.averageRecordedIncomeIndex =
            ((depositAmount + currentDepositAmount) * EXTRA_PRECISION) /
            sumOfRecordedDepositAmountDivRecordedIncomeIndex;

        // Update global values
        totalDeposit += depositAmount;
        {
            uint256 depositCap = GlobalDepositCap;
            require(depositCap == 0 || totalDeposit <= depositCap, "CAP");
        }
        totalInterestOwed += interestAmount;
        totalFeeOwed += feeAmount;

        // Emit event
        emit ETopupDeposit(
            sender,
            depositID,
            depositAmount,
            interestAmount,
            feeAmount
        );

        // Update vest
        mphMinter.updateVestForDeposit(
            depositID,
            currentDepositAmount,
            depositAmount
        );
    }

    function _topupDepositTransferFunds(address sender, uint256 depositAmount)
        internal
        virtual
    {
        ERC20 _stablecoin = stablecoin();

        // Transfer `depositAmount` stablecoin to DInterest
        _stablecoin.safeTransferFrom(sender, address(this), depositAmount);

        // Lend `depositAmount` stablecoin to money market
        MoneyMarket _moneyMarket = moneyMarket();
        _stablecoin.safeIncreaseAllowance(address(_moneyMarket), depositAmount);
        _moneyMarket.deposit(depositAmount);
    }

    /**
        @dev See {rolloverDeposit}
     */
    function _rolloverDeposit(
        address sender,
        uint64 depositID,
        uint64 maturationTimestamp,
        uint256 minimumInterestAmount,
        string memory uri
    ) internal virtual returns (uint64 newDepositID, uint256 interestAmount) {
        // withdraw from existing deposit
        uint256 withdrawnStablecoinAmount =
            _withdraw(sender, depositID, type(uint256).max, false, true);

        // deposit funds into a new deposit
        (newDepositID, interestAmount) = _deposit(
            sender,
            withdrawnStablecoinAmount,
            maturationTimestamp,
            true,
            minimumInterestAmount,
            uri
        );

        emit ERolloverDeposit(sender, depositID, newDepositID);
    }

    /**
        @dev See {withdraw}
        @param rollover True if being called from {_rolloverDeposit}, false otherwise
     */
    function _withdraw(
        address sender,
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
        ) = _withdrawRecordData(sender, depositID, virtualTokenAmount, early);
        return
            _withdrawTransferFunds(
                sender,
                _getDeposit(depositID).fundingID,
                withdrawAmount,
                feeAmount,
                fundingInterestAmount,
                refundAmount,
                rollover
            );
    }

    function _withdrawRecordData(
        address sender,
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
        require(virtualTokenAmount > 0, "BAD_AMOUNT");
        Deposit storage depositEntry = _getDeposit(depositID);
        if (early) {
            require(
                block.timestamp < depositEntry.maturationTimestamp,
                "MATURE"
            );
        } else {
            require(
                block.timestamp >= depositEntry.maturationTimestamp,
                "IMMATURE"
            );
        }
        require(depositNFT.ownerOf(depositID) == sender, "NOT_OWNER");

        // Check if withdrawing all funds
        {
            uint256 virtualTokenTotalSupply =
                depositEntry.virtualTokenTotalSupply;
            if (virtualTokenAmount > virtualTokenTotalSupply) {
                virtualTokenAmount = virtualTokenTotalSupply;
            }
        }

        // Compute token amounts
        uint256 interestRate = depositEntry.interestRate;
        uint256 feeRate = depositEntry.feeRate;
        uint256 depositAmount =
            virtualTokenAmount.div(interestRate + PRECISION);
        {
            uint256 interestAmount =
                early ? 0 : virtualTokenAmount - depositAmount;
            withdrawAmount = depositAmount + interestAmount;
        }
        if (early) {
            // apply fee to withdrawAmount
            uint256 earlyWithdrawFee =
                feeModel.getEarlyWithdrawFeeAmount(
                    address(this),
                    depositID,
                    withdrawAmount
                );
            feeAmount = earlyWithdrawFee;
            withdrawAmount -= earlyWithdrawFee;
        } else {
            feeAmount = depositAmount.mul(feeRate);
        }

        // Update global values
        totalDeposit -= depositAmount;
        totalInterestOwed -= virtualTokenAmount - depositAmount;
        totalFeeOwed -= depositAmount.mul(feeRate);

        // If deposit was funded, compute funding interest payout
        uint64 fundingID = depositEntry.fundingID;
        if (fundingID > 0) {
            Funding storage funding = _getFunding(fundingID);

            // Compute funded deposit amount before withdrawal
            uint256 recordedFundedPrincipalAmount =
                (fundingMultitoken.totalSupply(fundingID) *
                    funding.principalPerToken) / ULTRA_PRECISION;

            // Shrink funding principal per token value
            {
                uint256 totalPrincipal =
                    _depositVirtualTokenToPrincipal(
                        depositID,
                        depositEntry.virtualTokenTotalSupply
                    );
                uint256 totalPrincipalDecrease =
                    virtualTokenAmount + depositAmount.mul(feeRate);
                if (
                    totalPrincipal <=
                    totalPrincipalDecrease + recordedFundedPrincipalAmount
                ) {
                    // Not enough unfunded principal, need to decrease funding principal per token value
                    funding.principalPerToken = (totalPrincipal >=
                        totalPrincipalDecrease)
                        ? (funding.principalPerToken *
                            (totalPrincipal - totalPrincipalDecrease)) /
                            recordedFundedPrincipalAmount
                        : 0;
                }
            }

            // Compute interest payout + refund
            // and update relevant state
            (
                fundingInterestAmount,
                refundAmount
            ) = _computeAndUpdateFundingInterestAfterWithdraw(
                fundingID,
                recordedFundedPrincipalAmount,
                early
            );
        }

        // Update vest
        {
            uint256 depositAmountBeforeWithdrawal =
                _getDeposit(depositID).virtualTokenTotalSupply.div(
                    interestRate + PRECISION
                );
            mphMinter.updateVestForDeposit(
                depositID,
                depositAmountBeforeWithdrawal,
                0
            );
        }

        // Burn `virtualTokenAmount` deposit virtual tokens
        _getDeposit(depositID).virtualTokenTotalSupply -= virtualTokenAmount;

        // Emit event
        emit EWithdraw(sender, depositID, early, virtualTokenAmount, feeAmount);
    }

    function _withdrawTransferFunds(
        address sender,
        uint64 fundingID,
        uint256 withdrawAmount,
        uint256 feeAmount,
        uint256 fundingInterestAmount,
        uint256 refundAmount,
        bool rollover
    ) internal virtual returns (uint256 withdrawnStablecoinAmount) {
        ERC20 _stablecoin = stablecoin();

        // Withdraw funds from money market
        // Withdraws principal together with funding interest to save gas
        if (rollover) {
            // Rollover mode, don't withdraw `withdrawAmount` from moneyMarket

            // We do this because feePlusFundingInterest might
            // be slightly less due to rounding
            uint256 feePlusFundingInterest =
                moneyMarket().withdraw(feeAmount + fundingInterestAmount);
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
                moneyMarket().withdraw(
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
                fundingInterestAmount = 0;
            } else {
                // not enough to pay withdrawal
                // give everything to withdrawal
                withdrawnStablecoinAmount = actualWithdrawnAmount;
                feeAmount = 0;
                fundingInterestAmount = 0;
            }

            if (withdrawnStablecoinAmount > 0) {
                _stablecoin.safeTransfer(sender, withdrawnStablecoinAmount);
            }
        }

        // Send `feeAmount` stablecoin to feeModel beneficiary
        if (feeAmount > 0) {
            _stablecoin.safeTransfer(feeModel.beneficiary(), feeAmount);
        }

        // Distribute `fundingInterestAmount` stablecoins to funders
        if (fundingInterestAmount > 0) {
            _stablecoin.safeIncreaseAllowance(
                address(fundingMultitoken),
                fundingInterestAmount
            );
            fundingMultitoken.distributeDividends(
                fundingID,
                address(_stablecoin),
                fundingInterestAmount
            );
            // Mint funder rewards
            if (fundingInterestAmount > refundAmount) {
                _distributeFundingRewards(
                    fundingID,
                    fundingInterestAmount - refundAmount
                );
            }
        }
    }

    /**
        @dev See {fund}
     */
    function _fund(
        address sender,
        uint64 depositID,
        uint256 fundAmount,
        uint256 minPrincipalFunded
    )
        internal
        virtual
        returns (
            uint64 fundingID,
            uint256 fundingMultitokensMinted,
            uint256 actualFundAmount,
            uint256 principalFunded
        )
    {
        (
            fundingID,
            fundingMultitokensMinted,
            actualFundAmount,
            principalFunded
        ) = _fundRecordData(sender, depositID, fundAmount, minPrincipalFunded);
        _fundTransferFunds(sender, actualFundAmount);
    }

    function _fundRecordData(
        address sender,
        uint64 depositID,
        uint256 fundAmount,
        uint256 minPrincipalFunded
    )
        internal
        virtual
        returns (
            uint64 fundingID,
            uint256 fundingMultitokensMinted,
            uint256 actualFundAmount,
            uint256 principalFunded
        )
    {
        Deposit storage depositEntry = _getDeposit(depositID);
        fundingID = depositEntry.fundingID;
        uint256 incomeIndex = moneyMarket().incomeIndex();

        // Create funding struct if one doesn't exist
        {
            uint256 virtualTokenTotalSupply =
                depositEntry.virtualTokenTotalSupply;
            uint256 totalPrincipal =
                _depositVirtualTokenToPrincipal(
                    depositID,
                    virtualTokenTotalSupply
                );
            uint256 depositAmount =
                virtualTokenTotalSupply.div(
                    depositEntry.interestRate + PRECISION
                );
            if (
                fundingID == 0 || _getFunding(fundingID).principalPerToken == 0
            ) {
                // The first funder, create struct
                require(block.timestamp <= type(uint64).max, "OVERFLOW");
                fundingList.push(
                    Funding({
                        depositID: depositID,
                        lastInterestPayoutTimestamp: uint64(block.timestamp),
                        recordedMoneyMarketIncomeIndex: incomeIndex,
                        principalPerToken: ULTRA_PRECISION
                    })
                );
                require(fundingList.length <= type(uint64).max, "OVERFLOW");
                fundingID = uint64(fundingList.length);
                depositEntry.fundingID = fundingID;

                // Bound fundAmount upwards by the fixed rate yield amount
                uint256 bound =
                    calculateInterestAmount(
                        depositAmount,
                        depositEntry.maturationTimestamp - block.timestamp
                    );
                if (fundAmount > bound) {
                    fundAmount = bound;
                }

                principalFunded = (totalPrincipal * fundAmount) / bound;
                fundingMultitokensMinted = principalFunded;
            } else {
                // Not the first funder
                // Trigger interest payment for existing funders
                _payInterestToFunders(fundingID, incomeIndex);

                // Compute amount of principal to fund
                uint256 principalPerToken =
                    _getFunding(fundingID).principalPerToken;
                uint256 unfundedPrincipalAmount =
                    totalPrincipal -
                        (fundingMultitoken.totalSupply(fundingID) *
                            principalPerToken) /
                        ULTRA_PRECISION;

                // Bound fundAmount upwards by the fixed rate yield amount
                uint256 bound =
                    calculateInterestAmount(
                        (depositAmount * unfundedPrincipalAmount) /
                            totalPrincipal,
                        depositEntry.maturationTimestamp - block.timestamp
                    );
                if (fundAmount > bound) {
                    fundAmount = bound;
                }
                principalFunded =
                    (unfundedPrincipalAmount * fundAmount) /
                    bound;
                fundingMultitokensMinted =
                    (principalFunded * ULTRA_PRECISION) /
                    principalPerToken;
            }
        }

        // Check principalFunded is at least minPrincipalFunded
        require(principalFunded >= minPrincipalFunded, "MIN");

        // Mint funding multitoken
        fundingMultitoken.mint(sender, fundingID, fundingMultitokensMinted);

        // Update relevant values
        sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex +=
            (principalFunded * EXTRA_PRECISION) /
            incomeIndex;
        totalFundedPrincipalAmount += principalFunded;

        // Emit event
        emit EFund(sender, fundingID, fundAmount, fundingMultitokensMinted);

        actualFundAmount = fundAmount;
    }

    function _fundTransferFunds(address sender, uint256 fundAmount)
        internal
        virtual
    {
        ERC20 _stablecoin = stablecoin();

        // Transfer `fundAmount` stablecoins from sender
        _stablecoin.safeTransferFrom(sender, address(this), fundAmount);

        // Deposit `fundAmount` stablecoins into moneyMarket
        MoneyMarket _moneyMarket = moneyMarket();
        _stablecoin.safeIncreaseAllowance(address(_moneyMarket), fundAmount);
        _moneyMarket.deposit(fundAmount);
    }

    /**
        @dev See {payInterestToFunders}
        @param currentMoneyMarketIncomeIndex The moneyMarket's current incomeIndex
     */
    function _payInterestToFunders(
        uint64 fundingID,
        uint256 currentMoneyMarketIncomeIndex
    ) internal virtual returns (uint256 interestAmount) {
        Funding storage f = _getFunding(fundingID);
        {
            uint256 recordedMoneyMarketIncomeIndex =
                f.recordedMoneyMarketIncomeIndex;
            uint256 fundingTokenTotalSupply =
                fundingMultitoken.totalSupply(fundingID);
            uint256 recordedFundedPrincipalAmount =
                (fundingTokenTotalSupply * f.principalPerToken) /
                    ULTRA_PRECISION;

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
                (recordedFundedPrincipalAmount *
                    currentMoneyMarketIncomeIndex) /
                recordedMoneyMarketIncomeIndex -
                recordedFundedPrincipalAmount;
        }

        // Distribute interest to funders
        if (interestAmount > 0) {
            ERC20 _stablecoin = stablecoin();
            uint256 stablecoinPrecision = 10**uint256(_stablecoin.decimals());
            if (
                interestAmount >
                stablecoinPrecision / FUNDER_PAYOUT_THRESHOLD_DIVISOR
            ) {
                interestAmount = moneyMarket().withdraw(interestAmount);
                if (interestAmount > 0) {
                    _stablecoin.safeIncreaseAllowance(
                        address(fundingMultitoken),
                        interestAmount
                    );
                    fundingMultitoken.distributeDividends(
                        fundingID,
                        address(_stablecoin),
                        interestAmount
                    );

                    _distributeFundingRewards(fundingID, interestAmount);
                }
            } else {
                // interestAmount below minimum payout threshold, pay nothing
                emit EPayFundingInterest(fundingID, 0, 0);
                return 0;
            }
        }

        emit EPayFundingInterest(fundingID, interestAmount, 0);
    }

    /**
        @dev Mints MPH rewards to the holders of an FRB. If past the deposit maturation,
             only mint proportional to the time from the last distribution to the maturation.
        @param fundingID The ID of the funding
        @param rawInterestAmount The interest being distributed
     */
    function _distributeFundingRewards(
        uint64 fundingID,
        uint256 rawInterestAmount
    ) internal {
        Funding storage f = _getFunding(fundingID);

        // Mint funder rewards
        uint256 maturationTimestamp =
            _getDeposit(f.depositID).maturationTimestamp;
        if (block.timestamp > maturationTimestamp) {
            // past maturation, only mint proportionally to maturation - last payout
            uint256 lastInterestPayoutTimestamp = f.lastInterestPayoutTimestamp;
            if (lastInterestPayoutTimestamp < maturationTimestamp) {
                uint256 effectiveInterestAmount =
                    (rawInterestAmount *
                        (maturationTimestamp - lastInterestPayoutTimestamp)) /
                        (block.timestamp - lastInterestPayoutTimestamp);
                mphMinter.distributeFundingRewards(
                    fundingID,
                    effectiveInterestAmount
                );
            }
        } else {
            // before maturation, mint full amount
            mphMinter.distributeFundingRewards(fundingID, rawInterestAmount);
        }
        // update last payout timestamp
        require(block.timestamp <= type(uint64).max, "OVERFLOW");
        f.lastInterestPayoutTimestamp = uint64(block.timestamp);
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
        uint256 currentFundedPrincipalAmount =
            (fundingMultitoken.totalSupply(fundingID) * f.principalPerToken) /
                ULTRA_PRECISION;

        // Update funding values
        {
            uint256 recordedMoneyMarketIncomeIndex =
                f.recordedMoneyMarketIncomeIndex;
            uint256 currentMoneyMarketIncomeIndex = moneyMarket().incomeIndex();
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

            f.recordedMoneyMarketIncomeIndex = currentMoneyMarketIncomeIndex;
            totalFundedPrincipalAmount -=
                recordedFundedPrincipalAmount -
                currentFundedPrincipalAmount;

            // Compute interest to funders
            fundingInterestAmount =
                (recordedFundedPrincipalAmount *
                    currentMoneyMarketIncomeIndex) /
                recordedMoneyMarketIncomeIndex -
                recordedFundedPrincipalAmount;
        }

        // Add refund to interestAmount
        if (early) {
            Deposit storage depositEntry = _getDeposit(f.depositID);
            uint256 interestRate = depositEntry.interestRate;
            uint256 feeRate = depositEntry.feeRate;
            (, uint256 moneyMarketInterestRatePerSecond) =
                interestOracle.updateAndQuery();
            refundAmount = (recordedFundedPrincipalAmount -
                currentFundedPrincipalAmount)
                .mul(
                (moneyMarketInterestRatePerSecond *
                    (depositEntry.maturationTimestamp - block.timestamp))
                    .exp2() - PRECISION
            );
            uint256 maxRefundAmount =
                (recordedFundedPrincipalAmount - currentFundedPrincipalAmount)
                    .div(PRECISION + interestRate + feeRate)
                    .mul(interestRate + feeRate);
            refundAmount = refundAmount <= maxRefundAmount
                ? refundAmount
                : maxRefundAmount;
            fundingInterestAmount += refundAmount;
        }

        emit EPayFundingInterest(
            fundingID,
            fundingInterestAmount,
            refundAmount
        );
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
            virtualTokenAmount.div(depositInterestRate + PRECISION).mul(
                depositInterestRate + depositEntry.feeRate + PRECISION
            );
    }

    /**
        @dev See {Rescuable._authorizeRescue}
     */
    function _authorizeRescue(
        address, /*token*/
        address /*target*/
    ) internal view override onlyOwner {}

    /**
        @dev See {surplus}
        @param incomeIndex The moneyMarket's current incomeIndex
     */
    function _surplus(uint256 incomeIndex)
        internal
        virtual
        returns (bool isNegative, uint256 surplusAmount)
    {
        // compute totalInterestOwedToFunders
        uint256 currentValue =
            (incomeIndex *
                sumOfRecordedFundedPrincipalAmountDivRecordedIncomeIndex) /
                EXTRA_PRECISION;
        uint256 initialValue = totalFundedPrincipalAmount;
        uint256 totalInterestOwedToFunders;
        if (currentValue > initialValue) {
            totalInterestOwedToFunders = currentValue - initialValue;
        }

        // compute surplus
        uint256 totalValue = moneyMarket().totalValue(incomeIndex);
        uint256 totalOwed =
            totalDeposit +
                totalInterestOwed +
                totalFeeOwed +
                totalInterestOwedToFunders;
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
        Param setters (only callable by the owner)
     */
    function setFeeModel(address newValue) external onlyOwner {
        require(newValue.isContract(), "NOT_CONTRACT");
        feeModel = IFeeModel(newValue);
        emit ESetParamAddress(msg.sender, "feeModel", newValue);
    }

    function setInterestModel(address newValue) external onlyOwner {
        require(newValue.isContract(), "NOT_CONTRACT");
        interestModel = IInterestModel(newValue);
        emit ESetParamAddress(msg.sender, "interestModel", newValue);
    }

    function setInterestOracle(address newValue) external onlyOwner {
        require(newValue.isContract(), "NOT_CONTRACT");
        interestOracle = IInterestOracle(newValue);
        emit ESetParamAddress(msg.sender, "interestOracle", newValue);
    }

    function setRewards(address newValue) external onlyOwner {
        require(newValue.isContract(), "NOT_CONTRACT");
        moneyMarket().setRewards(newValue);
        emit ESetParamAddress(msg.sender, "moneyMarket.rewards", newValue);
    }

    function setMPHMinter(address newValue) external onlyOwner {
        require(newValue.isContract(), "NOT_CONTRACT");
        mphMinter = MPHMinter(newValue);
        emit ESetParamAddress(msg.sender, "mphMinter", newValue);
    }

    function setMaxDepositPeriod(uint64 newValue) external onlyOwner {
        require(newValue > 0, "BAD_VAL");
        MaxDepositPeriod = newValue;
        emit ESetParamUint(msg.sender, "MaxDepositPeriod", uint256(newValue));
    }

    function setMinDepositAmount(uint256 newValue) external onlyOwner {
        require(newValue > 0, "BAD_VAL");
        MinDepositAmount = newValue;
        emit ESetParamUint(msg.sender, "MinDepositAmount", newValue);
    }

    function setGlobalDepositCap(uint256 newValue) external onlyOwner {
        GlobalDepositCap = newValue;
        emit ESetParamUint(msg.sender, "GlobalDepositCap", newValue);
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

    function skimSurplus(address recipient) external onlyOwner {
        (bool isNegative, uint256 surplusMagnitude) = surplus();
        if (!isNegative) {
            surplusMagnitude = moneyMarket().withdraw(surplusMagnitude);
            stablecoin().safeTransfer(recipient, surplusMagnitude);
        }
    }

    function decreaseFeeForDeposit(uint64 depositID, uint256 newFeeRate)
        external
        onlyOwner
    {
        Deposit storage depositStorage = _getDeposit(depositID);
        uint256 feeRate = depositStorage.feeRate;
        uint256 interestRate = depositStorage.interestRate;
        uint256 virtualTokenTotalSupply =
            depositStorage.virtualTokenTotalSupply;
        require(newFeeRate < feeRate, "BAD_VAL");
        uint256 depositAmount =
            virtualTokenTotalSupply.div(interestRate + PRECISION);

        // update fee rate
        depositStorage.feeRate = newFeeRate;

        // update interest rate
        // fee reduction is allocated to interest
        uint256 reducedFeeAmount = depositAmount.mul(feeRate - newFeeRate);
        depositStorage.interestRate =
            interestRate +
            reducedFeeAmount.div(depositAmount);

        // update global amounts
        totalInterestOwed += reducedFeeAmount;
        totalFeeOwed -= reducedFeeAmount;
    }

    uint256[32] private __gap;
}
