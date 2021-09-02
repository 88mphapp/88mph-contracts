// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {
    ERC1155Receiver
} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";

import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";
import {PRBMathSD59x18} from "prb-math/contracts/PRBMathSD59x18.sol";

import {DInterest} from "../DInterest.sol";

contract PerpetualYieldToken is Initializable, IERC20, ERC1155Receiver {
    using PRBMathUD60x18 for uint256;
    using PRBMathSD59x18 for int256;

    /**
        @dev used for funding.principalPerToken
     */
    uint256 internal constant ULTRA_PRECISION = 2**128;

    mapping(address => uint256) private _logRawBalances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _logRawTotalSupply;

    string public name;
    string public symbol;
    uint8 public decimals;

    struct PYTParams {
        /**
            @notice epsilon = 2 ** (- epsilonNegExponent)
        */
        uint8 epsilonNegExponent;
        /**
            @notice The Unix timestamp of the contract's deployment
        */
        uint64 originTime;
        /**
            @notice The minimum time until maturation of the funding multitoken accepted by {mint}. In seconds.
        */
        uint64 minTimeTillMaturation;
    }
    PYTParams public params;

    DInterest public dInterest;

    event Mint(
        uint64 tokenId,
        uint256 fundingMultitokenAmount,
        uint256 mintAmount
    );

    function initialize(
        string calldata _name,
        string calldata _symbol,
        uint8 _decimals,
        uint8 _epsilonNegExponent,
        uint64 _minTimeTillMaturation,
        DInterest _dInterest
    ) external initializer {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;

        params = PYTParams({
            epsilonNegExponent: _epsilonNegExponent,
            originTime: SafeCast.toUint64(block.timestamp),
            minTimeTillMaturation: _minTimeTillMaturation
        });

        dInterest = _dInterest;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() external view override returns (uint256) {
        return _totalSupply(params);
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return _balanceOf(account, params);
    }

    function mint(uint64 tokenId, uint256 fundingMultitokenAmount)
        external
        returns (uint256 mintAmount)
    {
        // transfer fundingMultitokens from sender
        DInterest _dInterest = dInterest;
        _dInterest.fundingMultitoken().safeTransferFrom(
            msg.sender,
            address(this),
            tokenId,
            fundingMultitokenAmount,
            bytes("")
        );

        // mintAmount equals expected interest amount
        (, uint256 moneyMarketInterestRatePerSecond) =
            _dInterest.interestOracle().updateAndQuery();
        DInterest.Funding memory funding = _dInterest.getFunding(tokenId);
        uint64 maturationTimestamp =
            _dInterest.getDeposit(funding.depositID).maturationTimestamp;
        require(
            maturationTimestamp >=
                block.timestamp + params.minTimeTillMaturation,
            "PerpetualYieldToken: SHORT"
        );
        uint256 fundedPrincipalAmount =
            (fundingMultitokenAmount * funding.principalPerToken) /
                ULTRA_PRECISION;
        mintAmount = fundedPrincipalAmount.mul(
            (moneyMarketInterestRatePerSecond *
                (maturationTimestamp - block.timestamp))
                .exp2() - PRBMathUD60x18.SCALE
        );

        // mint tokens
        _mint(msg.sender, mintAmount);

        // emit event
        emit Mint(tokenId, fundingMultitokenAmount, mintAmount);
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount)
        external
        override
        returns (bool)
    {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        _approve(sender, msg.sender, currentAllowance - amount);

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue)
        external
        returns (bool)
    {
        _approve(
            msg.sender,
            spender,
            _allowances[msg.sender][spender] + addedValue
        );
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        external
        returns (bool)
    {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        _approve(msg.sender, spender, currentAllowance - subtractedValue);

        return true;
    }

    function onERC1155Received(
        address, /*operator*/
        address, /*from*/
        uint256, /*id*/
        uint256, /*value*/
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address, /*operator*/
        address, /*from*/
        uint256[] calldata, /*ids*/
        uint256[] calldata, /*values*/
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function _totalSupply(PYTParams memory _params)
        internal
        view
        returns (uint256)
    {
        return _logRawBalanceToBalance(_logRawTotalSupply, _params);
    }

    function _balanceOf(address account, PYTParams memory _params)
        internal
        view
        returns (uint256)
    {
        return _logRawBalanceToBalance(_logRawBalances[account], _params);
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        PYTParams memory _params = params;

        uint256 senderBalance = _balanceOf(sender, _params);
        require(
            senderBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        _logRawBalances[sender] = _balanceToLogRawBalance(
            senderBalance - amount,
            _params
        );
        _logRawBalances[recipient] = _balanceToLogRawBalance(
            _balanceOf(recipient, _params) + amount,
            _params
        );

        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        PYTParams memory _params = params;
        _logRawTotalSupply = _balanceToLogRawBalance(
            _totalSupply(_params) + amount,
            _params
        );
        _logRawBalances[account] = _balanceToLogRawBalance(
            _balanceOf(account, _params) + amount,
            _params
        );
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {}

    /**
        @dev Converts token balance to log2(rawBalance)
     */
    function _balanceToLogRawBalance(uint256 balance, PYTParams memory _params)
        internal
        view
        returns (uint256 logRawBalance)
    {
        // logRawBalance = log2(balance) + epsilonNegExponent * (block.timestamp - originTime)) / minTimeTillMaturation
        logRawBalance =
            balance.log2() +
            (PRBMathUD60x18.SCALE *
                _params.epsilonNegExponent *
                (block.timestamp - _params.originTime)) /
            _params.minTimeTillMaturation;
    }

    /**
        @dev Converts log2(rawBalance) to token balance
     */
    function _logRawBalanceToBalance(
        uint256 logRawBalance,
        PYTParams memory _params
    ) internal view returns (uint256 balance) {
        // balance = 2 ** (log2(rawBalance) - epsilonNegExponent * (block.timestamp - originTime)) / minTimeTillMaturation)
        balance = SafeCast.toUint256(
            (SafeCast.toInt256(logRawBalance) -
                SafeCast.toInt256(
                    (PRBMathUD60x18.SCALE *
                        _params.epsilonNegExponent *
                        (block.timestamp - _params.originTime)) /
                        _params.minTimeTillMaturation
                ))
                .exp2()
        );
    }

    uint256[43] private __gap;
}
