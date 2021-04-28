// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IFeeModel.sol";

contract PercentageFeeModel is IFeeModel, Ownable {
    uint256 internal constant PRECISION = 10**18;
    uint256 internal constant MAX_INTEREST_FEE = 50 * 10**16; // 50%
    uint256 internal constant MAX_EARLY_WITHDRAW_FEE = 5 * 10**16; // 2%

    struct FeeOverride {
        bool isOverridden;
        uint256 fee;
    }

    address payable public override beneficiary;
    mapping(address => mapping(uint256 => FeeOverride))
        public interestFeeOverride;
    mapping(address => mapping(uint256 => FeeOverride))
        public earlyWithdrawFeeOverride;

    uint256 public interestFee;
    uint256 public earlyWithdrawFee;

    event SetBeneficiary(address newBeneficiary);
    event SetInterestFee(uint256 newValue);
    event SetEarlyWithdrawFee(uint256 newValue);
    event SetOverrideInterestFee(
        address indexed pool,
        uint256 indexed depositID,
        uint256 newFee
    );
    event SetOverrideEarlyWithdrawFee(
        address indexed pool,
        uint256 indexed depositID,
        uint256 newFee
    );

    constructor(
        address payable _beneficiary,
        uint256 _interestFee,
        uint256 _earlyWithdrawFee
    ) {
        require(
            _beneficiary != address(0) &&
                _interestFee <= MAX_INTEREST_FEE &&
                _earlyWithdrawFee <= MAX_EARLY_WITHDRAW_FEE,
            "PercentageFeeModel: invalid input"
        );
        beneficiary = _beneficiary;
        interestFee = _interestFee;
        earlyWithdrawFee = _earlyWithdrawFee;
    }

    function getInterestFeeAmount(
        address pool,
        uint256 depositID,
        uint256 interestAmount
    ) external view override returns (uint256 feeAmount) {
        uint256 feeRate;
        FeeOverride memory feeOverride = interestFeeOverride[pool][depositID];
        if (feeOverride.isOverridden) {
            // fee has been overridden
            feeRate = feeOverride.fee;
        } else {
            // use default fee
            feeRate = interestFee;
        }
        return (interestAmount * feeRate) / PRECISION;
    }

    function getEarlyWithdrawFeeAmount(
        address pool,
        uint256 depositID,
        uint256 withdrawnDepositAmount
    ) external view override returns (uint256 feeAmount) {
        uint256 feeRate;
        FeeOverride memory feeOverride =
            earlyWithdrawFeeOverride[pool][depositID];
        if (feeOverride.isOverridden) {
            // fee has been overridden
            feeRate = feeOverride.fee;
        } else {
            // use default fee
            feeRate = earlyWithdrawFee;
        }
        return (withdrawnDepositAmount * feeRate) / PRECISION;
    }

    function setBeneficiary(address payable newValue) external onlyOwner {
        require(newValue != address(0), "PercentageFeeModel: 0 address");
        beneficiary = newValue;
        emit SetBeneficiary(newValue);
    }

    function setInterestFee(uint256 newValue) external onlyOwner {
        require(newValue <= MAX_INTEREST_FEE, "PercentageFeeModel: too big");
        interestFee = newValue;
        emit SetInterestFee(newValue);
    }

    function setEarlyWithdrawFee(uint256 newValue) external onlyOwner {
        require(
            newValue <= MAX_EARLY_WITHDRAW_FEE,
            "PercentageFeeModel: too big"
        );
        earlyWithdrawFee = newValue;
        emit SetEarlyWithdrawFee(newValue);
    }

    function overrideInterestFee(
        address pool,
        uint256 depositID,
        uint256 newFee
    ) external onlyOwner {
        require(newFee <= interestFee, "PercentageFeeModel: too big");
        interestFeeOverride[pool][depositID] = FeeOverride({
            isOverridden: true,
            fee: newFee
        });
        emit SetOverrideInterestFee(pool, depositID, newFee);
    }

    function overrideEarlyWithdrawFee(
        address pool,
        uint256 depositID,
        uint256 newFee
    ) external onlyOwner {
        require(newFee <= earlyWithdrawFee, "PercentageFeeModel: too big");
        earlyWithdrawFeeOverride[pool][depositID] = FeeOverride({
            isOverridden: true,
            fee: newFee
        });
        emit SetOverrideEarlyWithdrawFee(pool, depositID, newFee);
    }
}
