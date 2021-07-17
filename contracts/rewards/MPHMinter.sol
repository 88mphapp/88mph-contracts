// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    AddressUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {Vesting02} from "./Vesting02.sol";
import {FundingMultitoken} from "../tokens/FundingMultitoken.sol";
import {DecMath} from "../libs/DecMath.sol";
import {DInterest} from "../DInterest.sol";
import {MPHToken} from "./MPHToken.sol";

contract MPHMinter is AccessControlUpgradeable {
    using AddressUpgradeable for address;
    using DecMath for uint256;

    uint256 internal constant PRECISION = 10**18;
    bytes32 public constant WHITELISTER_ROLE = keccak256("WHITELISTER_ROLE");
    bytes32 public constant WHITELISTED_POOL_ROLE =
        keccak256("WHITELISTED_POOL_ROLE");
    bytes32 public constant LEGACY_MINTER_ROLE =
        keccak256("LEGACY_MINTER_ROLE");

    event ESetParamAddress(
        address indexed sender,
        string indexed paramName,
        address newValue
    );
    event ESetParamUint(
        address indexed sender,
        string indexed paramName,
        address pool,
        uint256 newValue
    );
    event MintDepositorReward(
        address indexed sender,
        address indexed to,
        uint256 depositorReward
    );
    event MintFunderReward(
        address indexed sender,
        address indexed to,
        uint256 funderReward
    );

    /**
        @notice The multiplier applied when minting MPH for a pool's depositor reward.
                Unit is MPH-wei per depositToken-wei per second. (wei here is the smallest decimal place)
                Scaled by 10^18.
                NOTE: The depositToken's decimals matter!
     */
    mapping(address => uint256) public poolDepositorRewardMintMultiplier;
    /**
        @notice The multiplier applied when minting MPH for a pool's funder reward.
                Unit is MPH-wei per depositToken-wei. (wei here is the smallest decimal place)
                Scaled by 10^18.
                NOTE: The depositToken's decimals matter!
     */
    mapping(address => uint256) public poolFunderRewardMultiplier;
    /**
        @notice Multiplier used for calculating dev reward
     */
    uint256 public devRewardMultiplier;
    /**
        @notice Multiplier used for calculating gov reward
     */
    uint256 public govRewardMultiplier;

    /**
        External contracts
     */
    MPHToken public mph;
    address public govTreasury;
    address public devWallet;
    Vesting02 public vesting02;

    function __MPHMinter_init(
        address _mph,
        address _govTreasury,
        address _devWallet,
        address _vesting02,
        uint256 _devRewardMultiplier,
        uint256 _govRewardMultiplier
    ) internal initializer {
        __AccessControl_init();
        __MPHMinter_init_unchained(
            _mph,
            _govTreasury,
            _devWallet,
            _vesting02,
            _devRewardMultiplier,
            _govRewardMultiplier
        );
    }

    function __MPHMinter_init_unchained(
        address _mph,
        address _govTreasury,
        address _devWallet,
        address _vesting02,
        uint256 _devRewardMultiplier,
        uint256 _govRewardMultiplier
    ) internal initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // only accounts with the whitelister role can whitelist pools
        _setRoleAdmin(WHITELISTED_POOL_ROLE, WHITELISTER_ROLE);

        mph = MPHToken(_mph);
        govTreasury = _govTreasury;
        devWallet = _devWallet;
        vesting02 = Vesting02(_vesting02);
        devRewardMultiplier = _devRewardMultiplier;
        govRewardMultiplier = _govRewardMultiplier;
    }

    function initialize(
        address _mph,
        address _govTreasury,
        address _devWallet,
        address _vesting02,
        uint256 _devRewardMultiplier,
        uint256 _govRewardMultiplier
    ) external initializer {
        __MPHMinter_init(
            _mph,
            _govTreasury,
            _devWallet,
            _vesting02,
            _devRewardMultiplier,
            _govRewardMultiplier
        );
    }

    function createVestForDeposit(address account, uint64 depositID)
        external
        onlyRole(WHITELISTED_POOL_ROLE)
    {
        vesting02.createVestForDeposit(
            account,
            msg.sender,
            depositID,
            poolDepositorRewardMintMultiplier[msg.sender]
        );
    }

    function updateVestForDeposit(
        uint64 depositID,
        uint256 currentDepositAmount,
        uint256 depositAmount
    ) external onlyRole(WHITELISTED_POOL_ROLE) {
        vesting02.updateVestForDeposit(
            msg.sender,
            depositID,
            currentDepositAmount,
            depositAmount,
            poolDepositorRewardMintMultiplier[msg.sender]
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
        uint256 devReward = amount.decmul(devRewardMultiplier);
        if (devReward > 0) {
            mph.ownerMint(devWallet, devReward);
        }
        uint256 govReward = amount.decmul(govRewardMultiplier);
        if (govReward > 0) {
            mph.ownerMint(govTreasury, govReward);
        }
        return amount;
    }

    function distributeFundingRewards(uint64 fundingID, uint256 interestAmount)
        external
        onlyRole(WHITELISTED_POOL_ROLE)
    {
        if (interestAmount == 0 || mph.owner() != address(this)) {
            return;
        }
        uint256 mintMPHAmount =
            interestAmount.decmul(poolFunderRewardMultiplier[msg.sender]);
        if (mintMPHAmount == 0) {
            return;
        }
        FundingMultitoken fundingMultitoken =
            DInterest(msg.sender).fundingMultitoken();
        mph.ownerMint(address(this), mintMPHAmount);
        mph.increaseAllowance(address(fundingMultitoken), mintMPHAmount);
        fundingMultitoken.distributeDividends(
            fundingID,
            address(mph),
            mintMPHAmount
        );

        uint256 devReward = mintMPHAmount.decmul(devRewardMultiplier);
        if (devReward > 0) {
            mph.ownerMint(devWallet, devReward);
        }
        uint256 govReward = mintMPHAmount.decmul(govRewardMultiplier);
        if (govReward > 0) {
            mph.ownerMint(govTreasury, govReward);
        }
    }

    /**
        @dev Used for supporting the v2 MPHMinterLegacy
     */
    function legacyMintFunderReward(
        address pool,
        address to,
        uint256 depositAmount,
        uint256 fundingCreationTimestamp,
        uint256 maturationTimestamp,
        uint256, /*interestPayoutAmount*/
        bool early
    ) external onlyRole(LEGACY_MINTER_ROLE) returns (uint256) {
        require(hasRole(WHITELISTED_POOL_ROLE, pool), "MPHMinter: not pool");

        if (mph.owner() != address(this)) {
            // not the owner of the MPH token, cannot mint
            return 0;
        }

        uint256 funderReward;
        uint256 devReward;
        uint256 govReward;
        if (!early) {
            funderReward = maturationTimestamp > fundingCreationTimestamp
                ? depositAmount *
                    (maturationTimestamp - fundingCreationTimestamp).decmul(
                        poolFunderRewardMultiplier[pool]
                    )
                : 0;
            devReward = funderReward.decmul(devRewardMultiplier);
            govReward = funderReward.decmul(govRewardMultiplier);
        } else {
            return 0;
        }

        // mint and vest funder reward
        if (funderReward > 0) {
            mph.ownerMint(to, funderReward);
        }
        if (devReward > 0) {
            mph.ownerMint(devWallet, devReward);
        }
        if (govReward > 0) {
            mph.ownerMint(govTreasury, govReward);
        }

        return funderReward;
    }

    /**
        Param setters
     */
    function setPoolDepositorRewardMintMultiplier(
        address pool,
        uint256 newMultiplier
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(pool.isContract(), "MPHMinter: pool not contract");
        poolDepositorRewardMintMultiplier[pool] = newMultiplier;
        emit ESetParamUint(
            msg.sender,
            "poolDepositorRewardMintMultiplier",
            pool,
            newMultiplier
        );
    }

    function setPoolFunderRewardMultiplier(address pool, uint256 newMultiplier)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(pool.isContract(), "MPHMinter: pool not contract");
        poolFunderRewardMultiplier[pool] = newMultiplier;
        emit ESetParamUint(
            msg.sender,
            "poolFunderRewardMultiplier",
            pool,
            newMultiplier
        );
    }

    function setDevRewardMultiplier(uint256 newMultiplier)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newMultiplier <= PRECISION, "MPHMinter: invalid multiplier");
        devRewardMultiplier = newMultiplier;
        emit ESetParamUint(
            msg.sender,
            "devRewardMultiplier",
            address(0),
            newMultiplier
        );
    }

    function setGovRewardMultiplier(uint256 newMultiplier)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newMultiplier <= PRECISION, "MPHMinter: invalid multiplier");
        govRewardMultiplier = newMultiplier;
        emit ESetParamUint(
            msg.sender,
            "govRewardMultiplier",
            address(0),
            newMultiplier
        );
    }

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

    function setVesting02(address newValue)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newValue.isContract(), "MPHMinter: not contract");
        vesting02 = Vesting02(newValue);
        emit ESetParamAddress(msg.sender, "vesting02", newValue);
    }

    uint256[42] private __gap;
}
