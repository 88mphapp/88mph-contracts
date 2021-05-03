// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    AddressUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {MPHToken} from "./MPHToken.sol";
import {IMPHIssuanceModel} from "../models/issuance/IMPHIssuanceModel.sol";
import {Vesting} from "./Vesting.sol";
import {Vesting02} from "./Vesting02.sol";

contract MPHMinterLegacy is AccessControlUpgradeable {
    using AddressUpgradeable for address;

    bytes32 public constant WHITELISTER_ROLE = keccak256("WHITELISTER_ROLE");
    bytes32 public constant WHITELISTED_POOL_ROLE =
        keccak256("WHITELISTED_POOL_ROLE");

    event ESetParamAddress(
        address indexed sender,
        string indexed paramName,
        address newValue
    );
    event MintDepositorReward(
        address indexed sender,
        address indexed to,
        uint256 depositorReward
    );
    event TakeBackDepositorReward(
        address indexed sender,
        address indexed from,
        uint256 takeBackAmount
    );
    event MintFunderReward(
        address indexed sender,
        address indexed to,
        uint256 funderReward
    );

    /**
        External contracts
     */
    MPHToken public mph;
    address public govTreasury;
    address public devWallet;
    IMPHIssuanceModel public issuanceModel;
    Vesting public vesting;

    function __MPHMinterLegacy_init(
        address _mph,
        address _govTreasury,
        address _devWallet,
        address _issuanceModel,
        address _vesting
    ) internal initializer {
        __AccessControl_init();
        __MPHMinterLegacy_init_unchained(
            _mph,
            _govTreasury,
            _devWallet,
            _issuanceModel,
            _vesting
        );
    }

    function __MPHMinterLegacy_init_unchained(
        address _mph,
        address _govTreasury,
        address _devWallet,
        address _issuanceModel,
        address _vesting
    ) internal initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // only accounts with the whitelister role can whitelist pools
        _setRoleAdmin(WHITELISTED_POOL_ROLE, WHITELISTER_ROLE);

        mph = MPHToken(_mph);
        govTreasury = _govTreasury;
        devWallet = _devWallet;
        issuanceModel = IMPHIssuanceModel(_issuanceModel);
        vesting = Vesting(_vesting);
    }

    /**
        v2 legacy functions
     */
    /**
        @notice Mints the MPH reward to a depositor upon deposit.
        @param  to The depositor
        @param  depositAmount The deposit amount in the pool's stablecoins
        @param  depositPeriodInSeconds The deposit's lock period in seconds
        @param  interestAmount The deposit's fixed-rate interest amount in the pool's stablecoins
        @return depositorReward The MPH amount to mint to the depositor
     */
    function mintDepositorReward(
        address to,
        uint256 depositAmount,
        uint256 depositPeriodInSeconds,
        uint256 interestAmount
    ) external onlyRole(WHITELISTED_POOL_ROLE) returns (uint256) {
        if (mph.owner() != address(this)) {
            // not the owner of the MPH token, cannot mint
            emit MintDepositorReward(msg.sender, to, 0);
            return 0;
        }

        (uint256 depositorReward, uint256 devReward, uint256 govReward) =
            issuanceModel.computeDepositorReward(
                msg.sender,
                depositAmount,
                depositPeriodInSeconds
            );
        if (depositorReward == 0 && devReward == 0 && govReward == 0) {
            return 0;
        }

        // mint and vest depositor reward
        if (depositorReward > 0) {
            mph.ownerMint(address(this), depositorReward);

            // vest the MPH to `to`
            mph.increaseAllowance(address(vesting), depositorReward);
            vesting.vest(to, depositorReward, depositPeriodInSeconds);
        }
        if (devReward > 0) {
            mph.ownerMint(devWallet, devReward);
        }
        if (govReward > 0) {
            mph.ownerMint(govTreasury, govReward);
        }

        emit MintDepositorReward(msg.sender, to, depositorReward);

        return depositorReward;
    }

    /**
        @notice Takes back MPH from depositor upon withdrawal.
                If takeBackAmount > devReward + govReward, the extra MPH should be burnt.
        @param  from The depositor
        @param  mintMPHAmount The MPH amount originally minted to the depositor as reward
        @param  early True if the deposit is withdrawn early, false if the deposit is mature
        @return takeBackAmount The MPH amount to take back from the depositor
     */
    function takeBackDepositorReward(
        address from,
        uint256 mintMPHAmount,
        bool early
    ) external onlyRole(WHITELISTED_POOL_ROLE) returns (uint256) {
        (uint256 takeBackAmount, uint256 devReward, uint256 govReward) =
            issuanceModel.computeTakeBackDepositorRewardAmount(
                mintMPHAmount,
                early
            );
        if (takeBackAmount == 0 && devReward == 0 && govReward == 0) {
            return 0;
        }
        require(
            takeBackAmount >= devReward + govReward,
            "MPHMinter: takeBackAmount < devReward + govReward"
        );
        if (takeBackAmount > 0) {
            mph.transferFrom(from, address(this), takeBackAmount);
        }
        if (devReward > 0) {
            mph.transfer(devWallet, devReward);
        }
        if (govReward > 0) {
            mph.transfer(govTreasury, govReward);
        }
        uint256 remainder = takeBackAmount - devReward - govReward;
        if (remainder > 0) {
            mph.burn(remainder);
        }

        emit TakeBackDepositorReward(msg.sender, from, takeBackAmount);

        return takeBackAmount;
    }

    /**
        @notice Mints the MPH reward to a deficit funder upon withdrawal of an underlying deposit.
        @param  to The funder
        @param  depositAmount The deposit amount in the pool's stablecoins
        @param  fundingCreationTimestamp The timestamp of the funding's creation, in seconds
        @param  maturationTimestamp The maturation timestamp of the deposit, in seconds
        @param  interestPayoutAmount The interest payout amount to the funder, in the pool's stablecoins.
                                     Includes the interest from other funded deposits.
        @param  early True if the deposit is withdrawn early, false if the deposit is mature
        @return funderReward The MPH amount to mint to the funder
     */
    function mintFunderReward(
        address to,
        uint256 depositAmount,
        uint256 fundingCreationTimestamp,
        uint256 maturationTimestamp,
        uint256 interestPayoutAmount,
        bool early
    ) external onlyRole(WHITELISTED_POOL_ROLE) returns (uint256) {
        if (mph.owner() != address(this)) {
            // not the owner of the MPH token, cannot mint
            emit MintDepositorReward(msg.sender, to, 0);
            return 0;
        }

        (uint256 funderReward, uint256 devReward, uint256 govReward) =
            issuanceModel.computeFunderReward(
                msg.sender,
                depositAmount,
                fundingCreationTimestamp,
                maturationTimestamp,
                early
            );
        if (funderReward == 0 && devReward == 0 && govReward == 0) {
            return 0;
        }

        // mint and vest funder reward
        if (funderReward > 0) {
            mph.ownerMint(address(this), funderReward);
            uint256 vestPeriodInSeconds =
                issuanceModel.poolFunderRewardVestPeriod(msg.sender);
            if (vestPeriodInSeconds == 0) {
                // no vesting, transfer to `to`
                mph.transfer(to, funderReward);
            } else {
                // vest the MPH to `to`
                mph.increaseAllowance(address(vesting), funderReward);
                vesting.vest(to, funderReward, vestPeriodInSeconds);
            }
        }

        if (devReward > 0) {
            mph.ownerMint(devWallet, devReward);
        }
        if (govReward > 0) {
            mph.ownerMint(govTreasury, govReward);
        }

        emit MintFunderReward(msg.sender, to, funderReward);

        return funderReward;
    }

    /**
        Param setters
     */
    function setGovTreasury(address newValue)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newValue != address(0), "MPHMinter: 0 address");
        govTreasury = newValue;
        emit ESetParamAddress(msg.sender, "govTreasury", newValue);
    }

    function setDevWallet(address newValue)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newValue != address(0), "MPHMinter: 0 address");
        devWallet = newValue;
        emit ESetParamAddress(msg.sender, "devWallet", newValue);
    }

    function setMPHTokenOwner(address newValue)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newValue != address(0), "MPHMinter: 0 address");
        mph.transferOwnership(newValue);
        emit ESetParamAddress(msg.sender, "mphTokenOwner", newValue);
    }

    function setMPHTokenOwnerToZero() external onlyRole(DEFAULT_ADMIN_ROLE) {
        mph.renounceOwnership();
        emit ESetParamAddress(msg.sender, "mphTokenOwner", address(0));
    }

    function setIssuanceModel(address newValue)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newValue.isContract(), "MPHMinter: not contract");
        issuanceModel = IMPHIssuanceModel(newValue);
        emit ESetParamAddress(msg.sender, "issuanceModel", newValue);
    }

    function setVesting(address newValue)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newValue.isContract(), "MPHMinter: not contract");
        vesting = Vesting(newValue);
        emit ESetParamAddress(msg.sender, "vesting", newValue);
    }

    uint256[45] private __gap;
}
