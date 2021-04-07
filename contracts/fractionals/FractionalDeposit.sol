// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../DInterest.sol";
import "../NFT.sol";
import "../rewards/MPHToken.sol";
import "../models/fee/IFeeModel.sol";

contract FractionalDeposit is
    ERC20Upgradeable,
    IERC721Receiver,
    OwnableUpgradeable
{
    using SafeERC20 for ERC20;

    DInterest public pool;
    NFT public nft;
    MPHToken public mph;
    uint256 public nftID;
    uint256 public mintMPHAmount;
    bool public active;
    uint8 public _decimals;

    event WithdrawDeposit();
    event RedeemShares(
        address indexed user,
        uint256 amountInShares,
        uint256 redeemStablecoinAmount
    );

    function init(
        address _pool,
        address _mph,
        uint256 _nftID,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external initializer {
        __ERC20_init(_tokenName, _tokenSymbol);
        __Ownable_init();

        pool = DInterest(_pool);
        mph = MPHToken(_mph);
        nft = NFT(pool.depositNFT());
        nftID = _nftID;
        active = true;

        // ensure contract is owner of NFT
        require(
            nft.ownerOf(_nftID) == address(this),
            "FractionalDeposit: not deposit owner"
        );

        // mint tokens to owner
        DInterest.Deposit memory deposit = pool.getDeposit(_nftID);
        require(deposit.active, "FractionalDeposit: deposit inactive");
        uint256 rawInterestOwed = deposit.interestOwed;
        uint256 interestAfterFee =
            rawInterestOwed - pool.feeModel().getFee(rawInterestOwed);
        uint256 initialSupply = deposit.amount + interestAfterFee;
        _mint(msg.sender, initialSupply);

        // transfer MPH from msg.sender
        mintMPHAmount = deposit.mintMPHAmount;
        mph.transferFrom(msg.sender, address(this), mintMPHAmount);

        // set decimals to be the same as the underlying stablecoin
        _decimals = ERC20(address(pool.stablecoin())).decimals();
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function withdrawDeposit(uint256 fundingID) external {
        _withdrawDeposit(fundingID);
    }

    function transferNFTToOwner() external {
        require(!active, "FractionalDeposit: deposit active");

        // transfer NFT to owner
        nft.safeTransferFrom(address(this), owner(), nftID);
    }

    function redeemShares(uint256 amountInShares, uint256 fundingID)
        external
        returns (uint256 redeemStablecoinAmount)
    {
        if (active) {
            // if deposit is still active, call withdrawDeposit()
            _withdrawDeposit(fundingID);
        }

        ERC20 stablecoin = pool.stablecoin();
        uint256 stablecoinBalance = stablecoin.balanceOf(address(this));
        redeemStablecoinAmount =
            (amountInShares * stablecoinBalance) /
            totalSupply();
        if (redeemStablecoinAmount > stablecoinBalance) {
            // prevent transferring too much
            redeemStablecoinAmount = stablecoinBalance;
        }

        // burn shares from sender
        _burn(msg.sender, amountInShares);

        // transfer pro rata withdrawn deposit
        stablecoin.safeTransfer(msg.sender, redeemStablecoinAmount);

        emit RedeemShares(msg.sender, amountInShares, redeemStablecoinAmount);
    }

    function _withdrawDeposit(uint256 fundingID) internal {
        require(active, "FractionalDeposit: deposit inactive");
        active = false;

        uint256 _nftID = nftID;

        // withdraw deposit from DInterest pool
        mph.increaseAllowance(address(pool.mphMinter()), mintMPHAmount);
        pool.withdraw(_nftID, fundingID);

        // return leftover MPH
        uint256 mphBalance = mph.balanceOf(address(this));
        if (mphBalance > 0) {
            mph.transfer(owner(), mphBalance);
        }

        emit WithdrawDeposit();
    }

    function onERC721Received(
        address, /*operator*/
        address, /*from*/
        uint256, /*tokenId*/
        bytes memory /*data*/
    ) public pure override returns (bytes4) {
        // only allow incoming transfer if not initialized
        return this.onERC721Received.selector;
    }
}
