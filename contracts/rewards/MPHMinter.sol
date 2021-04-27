// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "./MPHMinterLegacy.sol";
import "./Vesting02.sol";

contract MPHMinter is MPHMinterLegacy {
    using AddressUpgradeable for address;

    Vesting02 public vesting02;

    function __MPHMinter_init(
        address _mph,
        address _govTreasury,
        address _devWallet,
        address _issuanceModel,
        address _vesting,
        address _vesting02
    ) internal initializer {
        __MPHMinterLegacy_init(
            _mph,
            _govTreasury,
            _devWallet,
            _issuanceModel,
            _vesting
        );
        __MPHMinter_init_unchained(_vesting02);
    }

    function __MPHMinter_init_unchained(address _vesting02)
        internal
        initializer
    {
        vesting02 = Vesting02(_vesting02);
    }

    function initialize(
        address _mph,
        address _govTreasury,
        address _devWallet,
        address _issuanceModel,
        address _vesting,
        address _vesting02
    ) external initializer {
        __MPHMinter_init(
            _mph,
            _govTreasury,
            _devWallet,
            _issuanceModel,
            _vesting,
            _vesting02
        );
    }

    /**
        v3 functions
     */
    function createVestForDeposit(address account, uint256 depositID)
        external
        onlyRole(WHITELISTED_POOL_ROLE)
    {
        vesting02.createVestForDeposit(
            account,
            msg.sender,
            depositID,
            issuanceModel.poolDepositorRewardMintMultiplier(msg.sender)
        );
    }

    function updateVestForDeposit(
        uint256 depositID,
        uint256 currentDepositAmount,
        uint256 depositAmount
    ) external onlyRole(WHITELISTED_POOL_ROLE) {
        vesting02.updateVestForDeposit(
            depositID,
            currentDepositAmount,
            depositAmount,
            issuanceModel.poolDepositorRewardMintMultiplier(msg.sender)
        );
    }

    function mintVested(address account, uint256 amount)
        external
        returns (uint256 mintedAmount)
    {
        require(msg.sender == address(vesting02), "MPHMinter: not vesting02");
        if (mph.owner() != address(this)) {
            // not the owner of the MPH token, cannot mint
            return 0;
        }
        if (amount > 0) {
            mph.ownerMint(account, amount);
        }
        return amount;
    }

    /**
        Param setters
     */
    function setVesting02(address newValue)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newValue.isContract(), "MPHMinter: not contract");
        vesting02 = Vesting02(newValue);
        emit ESetParamAddress(msg.sender, "vesting02", newValue);
    }
}
