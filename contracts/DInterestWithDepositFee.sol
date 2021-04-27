// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "./DInterest.sol";

contract DInterestWithDepositFee is DInterest {
    using DecMath for uint256;
    using SafeERC20Upgradeable for ERC20Upgradeable;

    uint256 public DepositFee; // The deposit fee charged by the money market

    function __DInterestWithDepositFee_init(
        uint256 _MaxDepositPeriod,
        uint256 _MinDepositAmount,
        uint256 _DepositFee,
        address _moneyMarket,
        address _stablecoin,
        address _feeModel,
        address _interestModel,
        address _interestOracle,
        address _depositNFT,
        address _fundingMultitoken,
        address _mphMinter
    ) internal initializer {
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
        __DInterestWithDepositFee_init_unchained(_DepositFee);
    }

    function __DInterestWithDepositFee_init_unchained(uint256 _DepositFee)
        internal
        initializer
    {
        DepositFee = _DepositFee;
    }

    /**
        @param _MaxDepositPeriod The maximum deposit period, in seconds
        @param _MinDepositAmount The minimum deposit amount, in stablecoins
        @param _DepositFee The fee charged by the underlying money market
        @param _moneyMarket Address of IMoneyMarket that's used for generating interest (owner must be set to this DInterest contract)
        @param _stablecoin Address of the stablecoin used to store funds
        @param _feeModel Address of the FeeModel contract that determines how fees are charged
        @param _interestModel Address of the InterestModel contract that determines how much interest to offer
        @param _interestOracle Address of the InterestOracle contract that provides the average interest rate
        @param _depositNFT Address of the NFT representing ownership of deposits (owner must be set to this DInterest contract)
        @param _fundingMultitoken Address of the ERC1155 multitoken representing ownership of fundings (this DInterest contract must have the minter-burner role)
        @param _mphMinter Address of the contract for handling minting MPH to users
     */
    function init(
        uint256 _MaxDepositPeriod,
        uint256 _MinDepositAmount,
        uint256 _DepositFee,
        address _moneyMarket,
        address _stablecoin,
        address _feeModel,
        address _interestModel,
        address _interestOracle,
        address _depositNFT,
        address _fundingMultitoken,
        address _mphMinter
    ) external virtual initializer {
        __DInterestWithDepositFee_init(
            _MaxDepositPeriod,
            _MinDepositAmount,
            _DepositFee,
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
        Internal action functions
     */

    /**
        @dev See {deposit}
     */
    function _deposit(
        uint256 depositAmount,
        uint256 maturationTimestamp,
        bool rollover
    )
        internal
        virtual
        override
        returns (uint256 depositID, uint256 interestAmount)
    {
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

        // Apply deposit fee to the deposit amount
        uint256 depositAmountAfterFee = _applyDepositFee(depositAmount);

        // Calculate interest
        interestAmount = calculateInterestAmount(
            depositAmountAfterFee,
            depositPeriod
        );
        require(interestAmount > 0, "DInterest: interestAmount == 0");

        // Calculate fee
        uint256 feeAmount = feeModel.getFee(interestAmount);
        interestAmount -= feeAmount;

        // Mint MPH for msg.sender
        // TODO
        uint256 mintMPHAmount; /* =
            mphMinter.mintDepositorReward(
                msg.sender,
                depositAmount,
                depositPeriod,
                interestAmount
            );*/

        // Record deposit data
        deposits.push(
            Deposit({
                virtualTokenTotalSupply: depositAmountAfterFee + interestAmount,
                interestRate: interestAmount.decdiv(depositAmountAfterFee),
                feeRate: feeAmount.decdiv(interestAmount),
                mphRewardRate: mintMPHAmount.decdiv(depositAmountAfterFee),
                maturationTimestamp: maturationTimestamp,
                depositTimestamp: block.timestamp,
                fundingID: 0,
                averageRecordedIncomeIndex: moneyMarket.incomeIndex()
            })
        );

        // Update global values
        totalDeposit += depositAmountAfterFee;
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

        // Mint depositNFT
        depositNFT.mint(msg.sender, depositID);

        // Emit event
        emit EDeposit(
            msg.sender,
            depositID,
            depositAmountAfterFee,
            interestAmount,
            feeAmount,
            mintMPHAmount,
            maturationTimestamp
        );
    }

    /**
        @dev See {topupDeposit}
     */
    function _topupDeposit(uint256 depositID, uint256 depositAmount)
        internal
        virtual
        override
        returns (uint256 interestAmount)
    {
        Deposit memory depositEntry = _getDeposit(depositID);
        require(
            depositNFT.ownerOf(depositID) == msg.sender,
            "DInterest: not owner"
        );

        // Apply deposit fee to the deposit amount
        uint256 depositAmountAfterFee = _applyDepositFee(depositAmount);

        // underflow check prevents topups after maturation
        uint256 depositPeriod =
            depositEntry.maturationTimestamp - block.timestamp;

        // Calculate interest
        interestAmount = calculateInterestAmount(
            depositAmountAfterFee,
            depositPeriod
        );
        require(interestAmount > 0, "DInterest: interestAmount == 0");

        // Calculate fee
        uint256 feeAmount = feeModel.getFee(interestAmount);
        interestAmount -= feeAmount;

        // Mint MPH for msg.sender
        // TODO
        uint256 mintMPHAmount; /* =
            mphMinter.mintDepositorReward(
                msg.sender,
                depositAmount,
                depositPeriod,
                interestAmount
            );*/

        // Update deposit struct
        uint256 currentDepositAmount =
            depositEntry.virtualTokenTotalSupply.decdiv(
                depositEntry.interestRate + PRECISION
            );
        uint256 currentInterestAmount =
            depositEntry.virtualTokenTotalSupply - currentDepositAmount;
        depositEntry.virtualTokenTotalSupply +=
            depositAmountAfterFee +
            interestAmount;
        depositEntry.interestRate =
            (PRECISION *
                interestAmount +
                currentDepositAmount *
                depositEntry.interestRate) /
            (depositAmountAfterFee + currentDepositAmount);
        depositEntry.feeRate =
            (PRECISION *
                feeAmount +
                currentInterestAmount *
                depositEntry.feeRate) /
            (interestAmount + currentInterestAmount);
        depositEntry.mphRewardRate =
            (depositAmountAfterFee *
                mintMPHAmount.decdiv(depositAmountAfterFee) +
                currentDepositAmount *
                depositEntry.mphRewardRate) /
            (depositAmountAfterFee + currentDepositAmount);
        uint256 sumOfRecordedDepositAmountDivRecordedIncomeIndex =
            (currentDepositAmount * EXTRA_PRECISION) /
                depositEntry.averageRecordedIncomeIndex +
                (depositAmountAfterFee * EXTRA_PRECISION) /
                moneyMarket.incomeIndex();
        depositEntry.averageRecordedIncomeIndex =
            ((depositAmountAfterFee + currentDepositAmount) * EXTRA_PRECISION) /
            sumOfRecordedDepositAmountDivRecordedIncomeIndex;

        deposits[depositID - 1] = depositEntry;

        // Update global values
        totalDeposit += depositAmountAfterFee;
        totalInterestOwed += interestAmount;
        totalFeeOwed += feeAmount;

        // Transfer `depositAmount` stablecoin to DInterest
        stablecoin.safeTransferFrom(msg.sender, address(this), depositAmount);

        // Lend `depositAmount` stablecoin to money market
        stablecoin.safeIncreaseAllowance(address(moneyMarket), depositAmount);
        moneyMarket.deposit(depositAmount);

        // Emit event
        emit ETopupDeposit(
            msg.sender,
            depositID,
            depositAmountAfterFee,
            interestAmount,
            feeAmount,
            mintMPHAmount
        );
    }

    /**
        @dev See {fund}
     */
    function _fund(uint256 depositID, uint256 fundAmount)
        internal
        virtual
        override
        returns (uint256 fundingID)
    {
        Deposit storage depositEntry = _getDeposit(depositID);

        (bool isNegative, uint256 surplusMagnitude) = surplus();
        require(isNegative, "DInterest: No deficit available");

        (isNegative, surplusMagnitude) = rawSurplusOfDeposit(depositID);
        require(isNegative, "DInterest: No deficit available");
        uint256 fundAmountAfterFee = _applyDepositFee(fundAmount);
        if (fundAmountAfterFee > surplusMagnitude) {
            fundAmountAfterFee = surplusMagnitude;
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
            fundingID = fundingList.length;
            depositEntry.fundingID = fundingID;
            totalPrincipalToFund =
                (totalPrincipal * fundAmountAfterFee) /
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
            if (fundAmountAfterFee > surplusMagnitude) {
                fundAmountAfterFee = surplusMagnitude;
            }
            totalPrincipalToFund =
                (unfundedPrincipalAmount * fundAmountAfterFee) /
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
        emit EFund(msg.sender, fundingID, fundAmountAfterFee, mintTokenAmount);
    }

    /**
        Internal getter functions
     */

    /**
        @dev Applies a flat percentage deposit fee to a value.
        @param amount The before-fee amount
        @return The after-fee amount
     */
    function _applyDepositFee(uint256 amount)
        internal
        view
        virtual
        returns (uint256)
    {
        return amount.decmul(PRECISION - DepositFee);
    }

    /**
        Param setters (only callable by the owner)
     */

    function setDepositFee(uint256 newValue) external onlyOwner {
        require(newValue < PRECISION, "DInterestWithDepositFee: invalid value");
        DepositFee = newValue;
        emit ESetParamUint(msg.sender, "DepositFee", newValue);
    }
}
