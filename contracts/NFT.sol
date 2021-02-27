pragma solidity 0.5.17;

import "@openzeppelin/contracts/token/ERC721/ERC721Metadata.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";

contract NFT is ERC721Metadata("", ""), Ownable {
    /*
     * bytes4(keccak256('supportsInterface(bytes4)')) == 0x01ffc9a7
     */
    bytes4 private constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;
    /*
     *     bytes4(keccak256('name()')) == 0x06fdde03
     *     bytes4(keccak256('symbol()')) == 0x95d89b41
     *     bytes4(keccak256('tokenURI(uint256)')) == 0xc87b56dd
     *
     *     => 0x06fdde03 ^ 0x95d89b41 ^ 0xc87b56dd == 0x5b5e139f
     */
    bytes4 private constant _INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;
    /*
     *     bytes4(keccak256('balanceOf(address)')) == 0x70a08231
     *     bytes4(keccak256('ownerOf(uint256)')) == 0x6352211e
     *     bytes4(keccak256('approve(address,uint256)')) == 0x095ea7b3
     *     bytes4(keccak256('getApproved(uint256)')) == 0x081812fc
     *     bytes4(keccak256('setApprovalForAll(address,bool)')) == 0xa22cb465
     *     bytes4(keccak256('isApprovedForAll(address,address)')) == 0xe985e9c5
     *     bytes4(keccak256('transferFrom(address,address,uint256)')) == 0x23b872dd
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256)')) == 0x42842e0e
     *     bytes4(keccak256('safeTransferFrom(address,address,uint256,bytes)')) == 0xb88d4fde
     *
     *     => 0x70a08231 ^ 0x6352211e ^ 0x095ea7b3 ^ 0x081812fc ^
     *        0xa22cb465 ^ 0xe985e9c ^ 0x23b872dd ^ 0x42842e0e ^ 0xb88d4fde == 0x80ac58cd
     */
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    string internal _contractURI;
    string internal _tokenName;
    string internal _tokenSymbol;

    function init(
        address newOwner,
        string calldata tokenName,
        string calldata tokenSymbol
    ) external {
        _transferOwnership(newOwner);
        _tokenName = tokenName;
        _tokenSymbol = tokenSymbol;

        // register the supported interfaces to conform to ERC721 via ERC165
        _registerInterface(_INTERFACE_ID_ERC721_METADATA);

        // Derived contracts need only register support for their own interfaces,
        // we register support for ERC165 itself here
        _registerInterface(_INTERFACE_ID_ERC165);

        // register the supported interfaces to conform to ERC721 via ERC165
        _registerInterface(_INTERFACE_ID_ERC721);
    }

    /**
     * @dev Gets the token name.
     * @return string representing the token name
     */
    function name() external view returns (string memory) {
        return _tokenName;
    }

    /**
     * @dev Gets the token symbol.
     * @return string representing the token symbol
     */
    function symbol() external view returns (string memory) {
        return _tokenSymbol;
    }

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    function mint(address to, uint256 tokenId) external onlyOwner {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }

    function setContractURI(string calldata newURI) external onlyOwner {
        _contractURI = newURI;
    }

    function setTokenURI(uint256 tokenId, string calldata newURI)
        external
        onlyOwner
    {
        _setTokenURI(tokenId, newURI);
    }

    function setBaseURI(string calldata newURI) external onlyOwner {
        _setBaseURI(newURI);
    }
}
