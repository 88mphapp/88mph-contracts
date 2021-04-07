// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../DInterest.sol";
import "./FractionalDeposit.sol";
import "./FractionalDepositFactory.sol";

contract ZeroCouponBond is
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    IERC721Receiver
{
    using SafeERC20 for ERC20;

    bool public initialized;
    DInterest public pool;
    FractionalDepositFactory public fractionalDepositFactory;
    ERC20 public stablecoin;
    uint256 public maturationTimestamp;
    uint8 public _decimals;

    event Mint(
        address indexed sender,
        address indexed fractionalDepositAddress,
        uint256 amount
    );
    event RedeemFractionalDepositShares(
        address indexed sender,
        address indexed fractionalDepositAddress,
        uint256 fundingID
    );
    event RedeemStablecoin(address indexed sender, uint256 amount);

    function init(
        address _pool,
        address _fractionalDepositFactory,
        uint256 _maturationTimestamp,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external initializer {
        __ERC20_init(_tokenName, _tokenSymbol);
        __ReentrancyGuard_init();

        pool = DInterest(_pool);
        fractionalDepositFactory = FractionalDepositFactory(
            _fractionalDepositFactory
        );
        stablecoin = pool.stablecoin();
        maturationTimestamp = _maturationTimestamp;

        // set decimals to be the same as the underlying stablecoin
        _decimals = ERC20(address(pool.stablecoin())).decimals();

        // infinite approval to fractional deposit factory to save gas during minting with NFT
        pool.depositNFT().setApprovalForAll(_fractionalDepositFactory, true);
        fractionalDepositFactory.mph().approve(
            _fractionalDepositFactory,
            type(uint256).max
        );
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mintWithDepositNFT(
        uint256 nftID,
        string calldata fractionalDepositName,
        string calldata fractionalDepositSymbol
    )
        external
        nonReentrant
        returns (
            uint256 zeroCouponBondsAmount,
            FractionalDeposit fractionalDeposit
        )
    {
        // ensure the deposit's maturation time is on or before that of the ZCB
        DInterest.Deposit memory depositStruct = pool.getDeposit(nftID);
        uint256 depositMaturationTimestamp = depositStruct.maturationTimestamp;
        require(
            depositMaturationTimestamp <= maturationTimestamp,
            "ZeroCouponBonds: maturation too late"
        );

        // transfer MPH from `msg.sender`
        MPHToken mph = fractionalDepositFactory.mph();
        mph.transferFrom(
            msg.sender,
            address(this),
            depositStruct.mintMPHAmount
        );

        // transfer deposit NFT from `msg.sender`
        NFT depositNFT = pool.depositNFT();
        depositNFT.safeTransferFrom(msg.sender, address(this), nftID);

        // call fractionalDepositFactory to create fractional deposit using NFT
        fractionalDeposit = fractionalDepositFactory.createFractionalDeposit(
            address(pool),
            nftID,
            fractionalDepositName,
            fractionalDepositSymbol
        );
        fractionalDeposit.transferOwnership(msg.sender);

        // mint zero coupon bonds to `msg.sender`
        zeroCouponBondsAmount = fractionalDeposit.totalSupply();
        _mint(msg.sender, zeroCouponBondsAmount);

        emit Mint(
            msg.sender,
            address(fractionalDeposit),
            zeroCouponBondsAmount
        );
    }

    function redeemFractionalDepositShares(
        address fractionalDepositAddress,
        uint256 fundingID
    ) external nonReentrant {
        FractionalDeposit fractionalDeposit =
            FractionalDeposit(fractionalDepositAddress);

        uint256 balance = fractionalDeposit.balanceOf(address(this));
        fractionalDeposit.redeemShares(balance, fundingID);

        emit RedeemFractionalDepositShares(
            msg.sender,
            fractionalDepositAddress,
            fundingID
        );
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
    ) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
