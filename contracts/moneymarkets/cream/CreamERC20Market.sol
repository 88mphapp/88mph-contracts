// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../IMoneyMarket.sol";
import "../../libs/DecMath.sol";
import "../../libs/Rescuable.sol";
import "./imports/ICrERC20.sol";

contract CreamERC20Market is IMoneyMarket, OwnableUpgradeable, Rescuable {
    using DecMath for uint256;
    using SafeERC20Upgradeable for ERC20Upgradeable;
    using AddressUpgradeable for address;

    uint256 internal constant ERRCODE_OK = 0;

    ICrERC20 public cToken;
    ERC20Upgradeable public override stablecoin;

    function initialize(address _cToken, address _stablecoin)
        external
        initializer
    {
        __Ownable_init();

        // Verify input addresses
        require(
            _cToken.isContract() && _stablecoin.isContract(),
            "CreamERC20Market: An input address is not a contract"
        );

        cToken = ICrERC20(_cToken);
        stablecoin = ERC20Upgradeable(_stablecoin);
    }

    function deposit(uint256 amount) external override onlyOwner {
        require(amount > 0, "CreamERC20Market: amount is 0");

        // Transfer `amount` stablecoin from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Deposit `amount` stablecoin into cToken
        stablecoin.safeIncreaseAllowance(address(cToken), amount);
        require(
            cToken.mint(amount) == ERRCODE_OK,
            "CreamERC20Market: Failed to mint cTokens"
        );
    }

    function withdraw(uint256 amountInUnderlying)
        external
        override
        onlyOwner
        returns (uint256 actualAmountWithdrawn)
    {
        require(
            amountInUnderlying > 0,
            "CreamERC20Market: amountInUnderlying is 0"
        );

        // Withdraw `amountInUnderlying` stablecoin from cToken
        require(
            cToken.redeemUnderlying(amountInUnderlying) == ERRCODE_OK,
            "CreamERC20Market: Failed to redeem"
        );

        // Transfer `amountInUnderlying` stablecoin to `msg.sender`
        stablecoin.safeTransfer(msg.sender, amountInUnderlying);

        return amountInUnderlying;
    }

    function claimRewards() external override {}

    function totalValue() external override returns (uint256) {
        uint256 cTokenBalance = cToken.balanceOf(address(this));
        // Amount of stablecoin units that 1 unit of cToken can be exchanged for, scaled by 10^18
        uint256 cTokenPrice = cToken.exchangeRateCurrent();
        return cTokenBalance.decmul(cTokenPrice);
    }

    function incomeIndex() external override returns (uint256) {
        return cToken.exchangeRateCurrent();
    }

    function setRewards(address newValue) external override onlyOwner {}

    /**
        Rescuable
     */
    function _authorizeRescue(address token, address target)
        internal
        view
        override
    {
        require(token != address(cToken), "CreamERC20Market: no steal");
        require(msg.sender == owner(), "CreamERC20Market: not owner");
    }

    uint256[48] private __gap;
}
