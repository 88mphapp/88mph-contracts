pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../libs/CloneFactory.sol";
import "./FractionalDeposit.sol";
import "../DInterest.sol";
import "../NFT.sol";
import "../rewards/MPHToken.sol";

contract FractionalDepositFactory is CloneFactory, IERC721Receiver {
    address public template;
    MPHToken public mph;

    event CreateClone(address _clone);

    constructor(address _template, address _mph) public {
        template = _template;
        mph = MPHToken(_mph);
    }

    function createFractionalDeposit(
        address _pool,
        uint256 _nftID,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external returns (FractionalDeposit) {
        FractionalDeposit clone = FractionalDeposit(createClone(template));

        // transfer NFT from msg.sender to clone
        DInterest pool = DInterest(_pool);
        NFT nft = NFT(pool.depositNFT());
        nft.safeTransferFrom(msg.sender, address(this), _nftID);
        nft.safeTransferFrom(address(this), address(clone), _nftID);

        // transfer MPH reward from msg.sender
        DInterest.Deposit memory deposit = pool.getDeposit(_nftID);
        uint256 mintMPHAmount = deposit.mintMPHAmount;
        mph.transferFrom(msg.sender, address(this), mintMPHAmount);
        mph.increaseAllowance(address(clone), mintMPHAmount);

        // initialize
        clone.init(
            msg.sender,
            _pool,
            address(mph),
            _nftID,
            _tokenName,
            _tokenSymbol
        );

        emit CreateClone(address(clone));
        return clone;
    }

    function isFractionalDeposit(address query) external view returns (bool) {
        return isClone(template, query);
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
        return this.onERC721Received.selector;
    }
}
