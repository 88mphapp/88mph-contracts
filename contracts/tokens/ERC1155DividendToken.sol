// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./ERC1155Base.sol";

abstract contract ERC1155DividendToken is ERC1155Base {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;

    IERC20Upgradeable public target;

    // With `magnitude`, we can properly distribute dividends even if the amount of received target is small.
    // For more discussion about choosing the value of `magnitude`,
    //  see https://github.com/ethereum/EIPs/issues/1726#issuecomment-472352728
    uint256 internal constant magnitude = 2**128;

    mapping(uint256 => uint256) internal magnifiedDividendPerShare;

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
    mapping(uint256 => mapping(address => int256))
        internal magnifiedDividendCorrections;
    mapping(uint256 => mapping(address => uint256)) internal withdrawnDividends;

    /// @dev This event MUST emit when target is distributed to token holders.
    /// @param from The address which sends target to this contract.
    /// @param weiAmount The amount of distributed target in wei.
    event DividendsDistributed(
        uint256 indexed tokenID,
        address indexed from,
        uint256 weiAmount
    );

    /// @dev This event MUST emit when an address withdraws their dividend.
    /// @param to The address which withdraws target from this contract.
    /// @param weiAmount The amount of withdrawn target in wei.
    event DividendWithdrawn(
        uint256 indexed tokenID,
        address indexed to,
        uint256 weiAmount
    );

    function __ERC1155DividendToken_init(
        address targetAddress,
        address admin,
        string memory uri
    ) internal initializer {
        __ERC1155Base_init(admin, uri);
        __ERC1155DividendToken_init_unchained(targetAddress);
    }

    function __ERC1155DividendToken_init_unchained(address targetAddress)
        internal
        initializer
    {
        target = IERC20Upgradeable(targetAddress);
    }

    /**
        Public getters
     */

    /// @notice View the amount of dividend in wei that an address can withdraw.
    /// @param tokenID The token's ID.
    /// @param _owner The address of a token holder.
    /// @return The amount of dividend in wei that `_owner` can withdraw.
    function dividendOf(uint256 tokenID, address _owner)
        public
        view
        returns (uint256)
    {
        return _withdrawableDividendOf(tokenID, _owner);
    }

    /// @notice View the amount of dividend in wei that an address has withdrawn.
    /// @param tokenID The token's ID.
    /// @param _owner The address of a token holder.
    /// @return The amount of dividend in wei that `_owner` has withdrawn.
    function withdrawnDividendOf(uint256 tokenID, address _owner)
        public
        view
        returns (uint256)
    {
        return withdrawnDividends[tokenID][_owner];
    }

    /// @notice View the amount of dividend in wei that an address has earned in total.
    /// @dev accumulativeDividendOf(_owner) = _withdrawableDividendOf(_owner) + withdrawnDividendOf(_owner)
    /// = (magnifiedDividendPerShare * balanceOf(_owner) + magnifiedDividendCorrections[_owner]) / magnitude
    /// @param tokenID The token's ID.
    /// @param _owner The address of a token holder.
    /// @return The amount of dividend in wei that `_owner` has earned in total.
    function accumulativeDividendOf(uint256 tokenID, address _owner)
        public
        view
        returns (uint256)
    {
        return
            ((magnifiedDividendPerShare[tokenID] * balanceOf(_owner, tokenID))
                .toInt256() + magnifiedDividendCorrections[tokenID][_owner])
                .toUint256() / magnitude;
    }

    /**
        Internal functions
     */

    /// @notice View the amount of dividend in wei that an address can withdraw.
    /// @param tokenID The token's ID.
    /// @param _owner The address of a token holder.
    /// @return The amount of dividend in wei that `_owner` can withdraw.
    function _withdrawableDividendOf(uint256 tokenID, address _owner)
        internal
        view
        returns (uint256)
    {
        return
            accumulativeDividendOf(tokenID, _owner) -
            withdrawnDividends[tokenID][_owner];
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
    function _distributeDividends(uint256 tokenID, uint256 amount) internal {
        uint256 tokenTotalSupply = totalSupply(tokenID);
        require(tokenTotalSupply > 0);
        require(amount > 0);

        magnifiedDividendPerShare[tokenID] +=
            (amount * magnitude) /
            tokenTotalSupply;

        target.safeTransferFrom(msg.sender, address(this), amount);

        emit DividendsDistributed(tokenID, msg.sender, amount);
    }

    /// @notice Withdraws the target distributed to the sender.
    /// @dev It emits a `DividendWithdrawn` event if the amount of withdrawn target is greater than 0.
    function _withdrawDividend(uint256 tokenID, address user) internal {
        uint256 _withdrawableDividend = _withdrawableDividendOf(tokenID, user);
        if (_withdrawableDividend > 0) {
            withdrawnDividends[tokenID][user] += _withdrawableDividend;
            emit DividendWithdrawn(tokenID, user, _withdrawableDividend);
            target.safeTransfer(user, _withdrawableDividend);
        }
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

                magnifiedDividendCorrections[tokenID][
                    to
                ] -= (magnifiedDividendPerShare[tokenID] * amount).toInt256();
            }
        } else if (to == address(0)) {
            // Burn
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 tokenID = ids[i];
                uint256 amount = amounts[i];

                magnifiedDividendCorrections[tokenID][
                    to
                ] += (magnifiedDividendPerShare[tokenID] * amount).toInt256();
            }
        } else {
            // Transfer
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 tokenID = ids[i];
                uint256 amount = amounts[i];

                int256 _magCorrection =
                    (magnifiedDividendPerShare[tokenID] * amount).toInt256();
                // Retain the rewards
                magnifiedDividendCorrections[tokenID][from] += _magCorrection;
                magnifiedDividendCorrections[tokenID][to] -= _magCorrection;
            }
        }
    }
}
