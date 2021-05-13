// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "./DInterest.sol";

/**
    @dev A variant of DInterest that supports money markets with deposit fees
 */
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
    function initialize(
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
        uint64 maturationTimestamp,
        bool rollover
    )
        internal
        virtual
        override
        returns (uint64 depositID, uint256 interestAmount)
    {
        (depositID, interestAmount) = _depositRecordData(
            _applyDepositFee(depositAmount),
            maturationTimestamp
        );
        _depositTransferFunds(depositAmount, rollover);
    }

    /**
        @dev See {topupDeposit}
     */
    function _topupDeposit(uint64 depositID, uint256 depositAmount)
        internal
        virtual
        override
        returns (uint256 interestAmount)
    {
        interestAmount = _topupDepositRecordData(
            depositID,
            _applyDepositFee(depositAmount)
        );
        _topupDepositTransferFunds(depositAmount);
    }

    /**
        @dev See {fund}
     */
    function _fund(uint64 depositID, uint256 fundAmount)
        internal
        virtual
        override
        returns (uint64 fundingID)
    {
        uint256 actualFundAmount;
        (fundingID, actualFundAmount) = _fundRecordData(
            depositID,
            _applyDepositFee(fundAmount)
        );
        _fundTransferFunds(_unapplyDepositFee(fundAmount));
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
        @dev Unapplies a flat percentage deposit fee to a value.
        @param amount The after-fee amount
        @return The before-fee amount
     */
    function _unapplyDepositFee(uint256 amount)
        internal
        view
        virtual
        returns (uint256)
    {
        return amount.decdiv(PRECISION - DepositFee);
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
