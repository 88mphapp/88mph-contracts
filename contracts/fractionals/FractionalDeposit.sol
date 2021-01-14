pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "../DInterest.sol";
import "../NFT.sol";
import "../rewards/MPHToken.sol";
import "../models/fee/IFeeModel.sol";

contract FractionalDeposit is ERC20, IERC721Receiver, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    bool public initialized;
    DInterest public pool;
    NFT public nft;
    MPHToken public mph;
    uint256 public nftID;
    uint256 public mintMPHAmount;
    bool public active;
    string public name;
    string public symbol;
    uint8 public decimals;

    event WithdrawDeposit();
    event RedeemShares(
        address indexed user,
        uint256 amountInShares,
        uint256 redeemStablecoinAmount
    );

    function init(
        address _owner,
        address _pool,
        address _mph,
        uint256 _nftID,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external {
        require(!initialized, "FractionalDeposit: initialized");
        initialized = true;

        _transferOwnership(_owner);
        pool = DInterest(_pool);
        mph = MPHToken(_mph);
        nft = NFT(pool.depositNFT());
        nftID = _nftID;
        active = true;
        name = _tokenName;
        symbol = _tokenSymbol;

        // ensure contract is owner of NFT
        require(
            nft.ownerOf(_nftID) == address(this),
            "FractionalDeposit: not deposit owner"
        );

        // mint tokens to owner
        DInterest.Deposit memory deposit = pool.getDeposit(_nftID);
        require(deposit.active, "FractionalDeposit: deposit inactive");
        uint256 rawInterestOwed = deposit.interestOwed;
        uint256 interestAfterFee = rawInterestOwed.sub(pool.feeModel().getFee(rawInterestOwed));
        uint256 initialSupply = deposit.amount.add(interestAfterFee);
        _mint(_owner, initialSupply);

        // transfer MPH from msg.sender
        mintMPHAmount = deposit.mintMPHAmount;
        mph.transferFrom(msg.sender, address(this), mintMPHAmount);

        // set decimals to be the same as the underlying stablecoin
        decimals = ERC20Detailed(address(pool.stablecoin())).decimals();
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
        redeemStablecoinAmount = amountInShares.mul(stablecoinBalance).div(
            totalSupply()
        );
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

    /**
     * @notice Handle the receipt of an NFT
     * @dev The ERC721 smart contract calls this function on the recipient
     * after a {IERC721-safeTransferFrom}. This function MUST return the function selector,
     * otherwise the caller will revert the transaction. The selector to be
     * returned can be obtained as `this.onERC721Received.selector`. This
     * function MAY throw to revert and reject the transfer.
     * Note: the ERC721 contract address is always the message sender.
     * @param operator The address which called `safeTransferFrom` function
     * @param from The address which previously owned the token
     * @param tokenId The NFT identifier which is being transferred
     * @param data Additional data with no specified format
     * @return bytes4 `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data
    ) public returns (bytes4) {
        // only allow incoming transfer if not initialized
        require(!initialized, "FractionalDeposit: initialized");
        return this.onERC721Received.selector;
    }
}
