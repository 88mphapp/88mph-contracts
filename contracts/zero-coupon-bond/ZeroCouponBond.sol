// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "../tokens/NFT.sol";
import "../DInterest.sol";

contract ZeroCouponBond is
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    IERC721ReceiverUpgradeable
{
    using SafeERC20 for ERC20;

    DInterest public pool;
    ERC20 public stablecoin;
    NFT public depositNFT;
    uint256 public maturationTimestamp;
    uint8 public _decimals;

    event Mint(
        address indexed sender,
        uint256 indexed depositID,
        uint256 amount
    );
    event RedeemDeposit(address indexed sender, uint256 indexed depositID);
    event RedeemStablecoin(address indexed sender, uint256 amount);

    function init(
        address _pool,
        uint256 _maturationTimestamp,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external initializer {
        __ERC20_init(_tokenName, _tokenSymbol);
        __ReentrancyGuard_init();

        pool = DInterest(_pool);
        stablecoin = pool.stablecoin();
        depositNFT = pool.depositNFT();
        maturationTimestamp = _maturationTimestamp;

        // set decimals to be the same as the underlying stablecoin
        _decimals = ERC20(address(pool.stablecoin())).decimals();
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(uint256 depositID, uint256 depositVirtualTokenAmount)
        external
        nonReentrant
    {
        // ensure the deposit's maturation time is on or before that of the ZCB
        DInterest.Deposit memory depositStruct = pool.getDeposit(depositID);
        uint256 depositMaturationTimestamp = depositStruct.maturationTimestamp;
        require(
            depositMaturationTimestamp <= maturationTimestamp,
            "ZeroCouponBonds: maturation too late"
        );

        // transfer deposit NFT from `msg.sender`
        depositNFT.safeTransferFrom(msg.sender, address(this), depositID);

        // mint zero coupon bonds to `msg.sender`
        _mint(msg.sender, depositVirtualTokenAmount);

        emit Mint(msg.sender, depositID, depositVirtualTokenAmount);
    }

    function redeemDeposit(uint256 depositID) external nonReentrant {
        uint256 balance = pool.getDeposit(depositID).virtualTokenTotalSupply;
        pool.withdraw(depositID, balance);

        emit RedeemDeposit(msg.sender, depositID);
    }

    function redeemStablecoin(uint256 amount)
        external
        nonReentrant
        returns (uint256 actualRedeemedAmount)
    {
        require(
            block.timestamp >= maturationTimestamp,
            "ZeroCouponBond: not mature"
        );

        uint256 stablecoinBalance = stablecoin.balanceOf(address(this));
        actualRedeemedAmount = amount > stablecoinBalance
            ? stablecoinBalance
            : amount;

        // burn `actualRedeemedAmount` zero coupon bonds from `msg.sender`
        _burn(msg.sender, actualRedeemedAmount);

        // transfer `actualRedeemedAmount` stablecoins to `msg.sender`
        stablecoin.safeTransfer(msg.sender, actualRedeemedAmount);

        emit RedeemStablecoin(msg.sender, actualRedeemedAmount);
    }

    function onERC721Received(
        address, /*operator*/
        address, /*from*/
        uint256, /*tokenId*/
        bytes memory /*data*/
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
