// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {
    SafeCastUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ERC1155Base} from "./ERC1155Base.sol";

/**
    @notice An extension of ERC1155Base that allows distributing dividends to all holders
            of an token ID. Also supports multiple dividend tokens.
 */
abstract contract ERC1155DividendToken is ERC1155Base {
    using SafeERC20 for IERC20;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;

    struct DividendTokenData {
        address dividendToken;
        mapping(uint256 => uint256) magnifiedDividendPerShare;
        // About dividendCorrection:
        // If the token balance of a `_user` is never changed, the dividend of `_user` can be computed with:
        //   `dividendOf(_user) = dividendPerShare * balanceOf(_user)`.
        // When `balanceOf(_user)` is changed (via minting/burning/transferring tokens),
        //   `dividendOf(_user)` should not be changed,
        //   but the computed value of `dividendPerShare * balanceOf(_user)` is changed.
        // To keep the `dividendOf(_user)` unchanged, we add a correction term:
        //   `dividendOf(_user) = dividendPerShare * balanceOf(_user) + dividendCorrectionOf(_user)`,
        //   where `dividendCorrectionOf(_user)` is updated whenever `balanceOf(_user)` is changed:
        //   `dividendCorrectionOf(_user) = dividendPerShare * (old balanceOf(_user)) - (new balanceOf(_user))`.
        // So now `dividendOf(_user)` returns the same value before and after `balanceOf(_user)` is changed.
        mapping(uint256 => mapping(address => int256)) magnifiedDividendCorrections;
        mapping(uint256 => mapping(address => uint256)) withdrawnDividends;
    }

    // With `magnitude`, we can properly distribute dividends even if the amount of received target is small.
    // For more discussion about choosing the value of `magnitude`,
    //  see https://github.com/ethereum/EIPs/issues/1726#issuecomment-472352728
    uint256 internal constant magnitude = 2**128;

    /**
        @notice The list of tokens that can be distributed to token holders as dividend. 1-indexed.
     */
    mapping(uint256 => DividendTokenData) public dividendTokenDataList;
    uint256 public dividendTokenDataListLength;
    /**
        @notice The dividend token address to its key in {dividendTokenDataList}
     */
    mapping(address => uint256) public dividendTokenToDataID;

    /// @dev This event MUST emit when target is distributed to token holders.
    /// @param from The address which sends target to this contract.
    /// @param weiAmount The amount of distributed target in wei.
    event DividendsDistributed(
        uint256 indexed tokenID,
        address indexed from,
        address indexed dividendToken,
        uint256 weiAmount
    );

    /// @dev This event MUST emit when an address withdraws their dividend.
    /// @param to The address which withdraws target from this contract.
    /// @param weiAmount The amount of withdrawn target in wei.
    event DividendWithdrawn(
        uint256 indexed tokenID,
        address indexed to,
        address indexed dividendToken,
        uint256 weiAmount
    );

    function __ERC1155DividendToken_init(
        address[] memory dividendTokens,
        address admin,
        string memory uri
    ) internal initializer {
        __ERC1155Base_init(admin, uri);
        __ERC1155DividendToken_init_unchained(dividendTokens);
    }

    function __ERC1155DividendToken_init_unchained(
        address[] memory dividendTokens
    ) internal initializer {
        dividendTokenDataListLength = dividendTokens.length;
        for (uint256 i = 0; i < dividendTokens.length; i++) {
            dividendTokenDataList[i + 1].dividendToken = dividendTokens[i];
            dividendTokenToDataID[dividendTokens[i]] = i + 1;
        }
    }

    /**
        Public getters
     */

    /// @notice View the amount of dividend in wei that an address can withdraw.
    /// @param tokenID The token's ID.
    /// @param dividendToken The token the dividend is in
    /// @param _owner The address of a token holder.
    /// @return The amount of dividend in wei that `_owner` can withdraw.
    function dividendOf(
        uint256 tokenID,
        address dividendToken,
        address _owner
    ) public view returns (uint256) {
        return _withdrawableDividendOf(tokenID, dividendToken, _owner);
    }

    /// @notice View the amount of dividend in wei that an address has withdrawn.
    /// @param tokenID The token's ID.
    /// @param dividendToken The token the dividend is in
    /// @param _owner The address of a token holder.
    /// @return The amount of dividend in wei that `_owner` has withdrawn.
    function withdrawnDividendOf(
        uint256 tokenID,
        address dividendToken,
        address _owner
    ) public view returns (uint256) {
        uint256 dividendTokenDataID = dividendTokenToDataID[dividendToken];
        if (dividendTokenDataID == 0) {
            return 0;
        }
        DividendTokenData storage data =
            dividendTokenDataList[dividendTokenDataID];
        return data.withdrawnDividends[tokenID][_owner];
    }

    /// @notice View the amount of dividend in wei that an address has earned in total.
    /// @dev accumulativeDividendOf(_owner) = _withdrawableDividendOf(_owner) + withdrawnDividendOf(_owner)
    /// = (magnifiedDividendPerShare * balanceOf(_owner) + magnifiedDividendCorrections[_owner]) / magnitude
    /// @param tokenID The token's ID.
    /// @param dividendToken The token the dividend is in
    /// @param _owner The address of a token holder.
    /// @return The amount of dividend in wei that `_owner` has earned in total.
    function accumulativeDividendOf(
        uint256 tokenID,
        address dividendToken,
        address _owner
    ) public view returns (uint256) {
        uint256 dividendTokenDataID = dividendTokenToDataID[dividendToken];
        if (dividendTokenDataID == 0) {
            return 0;
        }
        DividendTokenData storage data =
            dividendTokenDataList[dividendTokenDataID];
        return
            ((data.magnifiedDividendPerShare[tokenID] *
                balanceOf(_owner, tokenID))
                .toInt256() +
                data.magnifiedDividendCorrections[tokenID][_owner])
                .toUint256() / magnitude;
    }

    /**
        Internal functions
     */

    /// @notice View the amount of dividend in wei that an address can withdraw.
    /// @param tokenID The token's ID.
    /// @param dividendToken The token the dividend is in
    /// @param _owner The address of a token holder.
    /// @return The amount of dividend in wei that `_owner` can withdraw.
    function _withdrawableDividendOf(
        uint256 tokenID,
        address dividendToken,
        address _owner
    ) internal view returns (uint256) {
        uint256 dividendTokenDataID = dividendTokenToDataID[dividendToken];
        if (dividendTokenDataID == 0) {
            return 0;
        }
        DividendTokenData storage data =
            dividendTokenDataList[dividendTokenDataID];
        return
            accumulativeDividendOf(tokenID, dividendToken, _owner) -
            data.withdrawnDividends[tokenID][_owner];
    }

    /// @notice Distributes target to token holders as dividends.
    /// @dev It reverts if the total supply of tokens is 0.
    /// It emits the `DividendsDistributed` event if the amount of received target is greater than 0.
    /// About undistributed target tokens:
    ///   In each distribution, there is a small amount of target not distributed,
    ///     the magnified amount of which is
    ///     `(amount * magnitude) % totalSupply()`.
    ///   With a well-chosen `magnitude`, the amount of undistributed target
    ///     (de-magnified) in a distribution can be less than 1 wei.
    ///   We can actually keep track of the undistributed target in a distribution
    ///     and try to distribute it in the next distribution,
    ///     but keeping track of such data on-chain costs much more than
    ///     the saved target, so we don't do that.
    function _distributeDividends(
        uint256 tokenID,
        address dividendToken,
        uint256 amount
    ) internal {
        uint256 tokenTotalSupply = totalSupply(tokenID);
        require(tokenTotalSupply > 0);
        require(amount > 0);

        uint256 dividendTokenDataID = dividendTokenToDataID[dividendToken];
        require(
            dividendTokenDataID != 0,
            "ERC1155DividendToken: invalid dividendToken"
        );
        DividendTokenData storage data =
            dividendTokenDataList[dividendTokenDataID];

        data.magnifiedDividendPerShare[tokenID] +=
            (amount * magnitude) /
            tokenTotalSupply;

        IERC20(dividendToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        emit DividendsDistributed(tokenID, msg.sender, dividendToken, amount);
    }

    /// @notice Withdraws the target distributed to the sender.
    /// @dev It emits a `DividendWithdrawn` event if the amount of withdrawn target is greater than 0.
    function _withdrawDividend(
        uint256 tokenID,
        address dividendToken,
        address user
    ) internal {
        uint256 _withdrawableDividend =
            _withdrawableDividendOf(tokenID, dividendToken, user);
        if (_withdrawableDividend > 0) {
            uint256 dividendTokenDataID = dividendTokenToDataID[dividendToken];
            require(
                dividendTokenDataID != 0,
                "ERC1155DividendToken: invalid dividendToken"
            );
            DividendTokenData storage data =
                dividendTokenDataList[dividendTokenDataID];
            data.withdrawnDividends[tokenID][user] += _withdrawableDividend;
            emit DividendWithdrawn(
                tokenID,
                user,
                dividendToken,
                _withdrawableDividend
            );
            IERC20(dividendToken).safeTransfer(user, _withdrawableDividend);
        }
    }

    function _registerDividendToken(address dividendToken)
        internal
        returns (uint256 newDividendTokenDataID)
    {
        require(
            dividendTokenToDataID[dividendToken] == 0,
            "ERC1155DividendToken: already registered"
        );
        dividendTokenDataListLength++;
        newDividendTokenDataID = dividendTokenDataListLength;
        dividendTokenDataList[newDividendTokenDataID]
            .dividendToken = dividendToken;
        dividendTokenToDataID[dividendToken] = newDividendTokenDataID;
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155Base) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        if (from == address(0)) {
            // Mint
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 tokenID = ids[i];
                uint256 amount = amounts[i];

                for (uint256 j = 1; j <= dividendTokenDataListLength; j++) {
                    DividendTokenData storage dividendTokenData =
                        dividendTokenDataList[j];
                    dividendTokenData.magnifiedDividendCorrections[tokenID][
                        to
                    ] -= (dividendTokenData.magnifiedDividendPerShare[tokenID] *
                        amount)
                        .toInt256();
                }
            }
        } else if (to == address(0)) {
            // Burn
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 tokenID = ids[i];
                uint256 amount = amounts[i];

                for (uint256 j = 1; j <= dividendTokenDataListLength; j++) {
                    DividendTokenData storage dividendTokenData =
                        dividendTokenDataList[j];
                    dividendTokenData.magnifiedDividendCorrections[tokenID][
                        from
                    ] += (dividendTokenData.magnifiedDividendPerShare[tokenID] *
                        amount)
                        .toInt256();
                }
            }
        } else {
            // Transfer
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 tokenID = ids[i];
                uint256 amount = amounts[i];

                for (uint256 j = 1; j <= dividendTokenDataListLength; j++) {
                    DividendTokenData storage dividendTokenData =
                        dividendTokenDataList[j];
                    int256 _magCorrection =
                        (dividendTokenData.magnifiedDividendPerShare[tokenID] *
                            amount)
                            .toInt256();
                    // Retain the rewards
                    dividendTokenData.magnifiedDividendCorrections[tokenID][
                        from
                    ] += _magCorrection;
                    dividendTokenData.magnifiedDividendCorrections[tokenID][
                        to
                    ] -= _magCorrection;
                }
            }
        }
    }

    uint256[47] private __gap;
}
