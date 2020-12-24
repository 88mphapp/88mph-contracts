pragma solidity 0.5.17;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../DInterest.sol";
import "../NFT.sol";
import "../rewards/MPHToken.sol";

contract FractionalDeposit is ERC20, IERC721Receiver {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    bool public initialized;
    address public creator; // will receive NFT upon deposit withdrawal
    DInterest public pool;
    NFT public nft;
    MPHToken public mph;
    uint256 public nftID;
    bool public active;
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    event WithdrawDeposit();
    event RedeemShares(
        address indexed user,
        uint256 amountInShares,
        uint256 redeemStablecoinAmount
    );

    function init(
        address _creator,
        address _pool,
        address _mph,
        uint256 _nftID,
        uint256 _totalSupply,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external {
        require(!initialized, "FractionalDeposit: initialized");
        initialized = true;

        creator = _creator;
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

        // mint totalSupply tokens to creator
        require(_totalSupply > 0, "FractionalDeposit: 0 supply");
        _mint(_creator, _totalSupply);
    }

    function withdrawDeposit(uint256 mphTakebackAmount, uint256 fundingID) external {
        require(active, "FractionalDeposit: deposit inactive");
        active = false;

        uint256 _nftID = nftID;

        // transfer MPH from msg.sender
        mph.transferFrom(msg.sender, address(this), mphTakebackAmount);

        // withdraw deposit from DInterest pool
        mph.increaseAllowance(address(pool.mphMinter()), mphTakebackAmount);
        pool.withdraw(_nftID, fundingID);

        // return possible leftover MPH
        uint256 mphBalance = mph.balanceOf(address(this));
        if (mphBalance > 0) {
            mph.transfer(msg.sender, mphBalance);
        }

        emit WithdrawDeposit();
    }

    function transferNFTToCreator() external {
        require(!active, "FractionalDeposit: deposit active");

        // transfer NFT to creator
        nft.transferFrom(address(this), creator, nftID);
    }

    function redeemShares(uint256 amountInShares)
        external
        returns (uint256 redeemStablecoinAmount)
    {
        require(!active, "FractionalDeposit: deposit active");

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
