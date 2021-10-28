// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {MPHMinter} from "./MPHMinter.sol";
import {MPHToken} from "./MPHToken.sol";

/**
    @title MPHConverter
    @notice Converts between the chain's native MPH token and foreign versions bridged from other chains
    @dev Each foreign token has a daily limit for converting into the native token in order to limit the
    effect of potential hacks of a deployment on another chain or a bridge. Also pausable.
 */
contract MPHConverter is PausableUpgradeable, OwnableUpgradeable {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    struct DailyConvertLimit {
        uint96 limitAmount;
        uint96 convertedAmountToday;
        uint64 lastResetTimestamp;
    }

    MPHMinter public mphMinter;
    mapping(address => bool) public isWhitelistedForeignToken;
    mapping(address => DailyConvertLimit)
        public foreignToNativeDailyConvertLimit;

    modifier onlyWhitelistedForeignToken(IERC20 foreignToken) {
        require(
            isWhitelistedForeignToken[address(foreignToken)],
            "MPHConverter: NOT_WHITELISTED"
        );
        _;
    }

    modifier updateDailyConvertLimit(IERC20 foreignToken, uint256 amount) {
        DailyConvertLimit memory limit =
            foreignToNativeDailyConvertLimit[address(foreignToken)];
        if (limit.lastResetTimestamp + 1 days <= block.timestamp) {
            // more than 1 day after the last reset
            // clear usage
            limit.lastResetTimestamp = block.timestamp.toUint64();
            limit.convertedAmountToday = 0;
        }
        limit.convertedAmountToday += amount.toUint96();
        require(
            limit.convertedAmountToday <= limit.limitAmount,
            "MPHConverter: LIMIT"
        );
        foreignToNativeDailyConvertLimit[address(foreignToken)] = limit;
        _;
    }

    function initialize(MPHMinter _mphMinter) external initializer {
        __Pausable_init();
        __Ownable_init();

        mphMinter = _mphMinter;
    }

    /**
        Owner functions
     */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setForeignTokenWhitelist(IERC20 foreignToken, bool isWhitelisted)
        external
        onlyOwner
    {
        isWhitelistedForeignToken[address(foreignToken)] = isWhitelisted;
    }

    function setForeignToNativeDailyConvertLimit(
        IERC20 foreignToken,
        uint96 newLimitAmount
    ) external onlyOwner {
        foreignToNativeDailyConvertLimit[address(foreignToken)]
            .limitAmount = newLimitAmount;
    }

    /**
        Convert functions
     */

    function convertNativeTokenToForeign(IERC20 foreignToken, uint256 amount)
        external
        whenNotPaused
        onlyWhitelistedForeignToken(foreignToken)
    {
        // transfer native tokens from sender
        IERC20(address(mphMinter.mph())).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        // transfer foreign tokens to sender
        foreignToken.safeTransfer(msg.sender, amount);
    }

    function convertForeignTokenToNative(IERC20 foreignToken, uint256 amount)
        external
        whenNotPaused
        onlyWhitelistedForeignToken(foreignToken)
        updateDailyConvertLimit(foreignToken, amount)
    {
        // transfer foreign tokens from sender
        foreignToken.safeTransferFrom(msg.sender, address(this), amount);

        // transfer native tokens to sender
        IERC20 _nativeToken = IERC20(address(mphMinter.mph()));
        uint256 nativeTokenBalance = _nativeToken.balanceOf(address(this));
        if (nativeTokenBalance >= amount) {
            // contract has enough native tokens, do simple transfer
            _nativeToken.safeTransfer(msg.sender, amount);
        } else if (nativeTokenBalance > 0) {
            // contract doesn't have enough, transfer balance & mint remainder
            _nativeToken.safeTransfer(msg.sender, nativeTokenBalance);
            mphMinter.converterMint(msg.sender, amount - nativeTokenBalance);
        } else {
            // contract has no native tokens, mint amount
            mphMinter.converterMint(msg.sender, amount);
        }
    }
}
