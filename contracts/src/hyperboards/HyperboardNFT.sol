// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
import { IERC20 } from "oz-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "oz-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721 } from "oz-contracts/contracts/token/ERC721/ERC721.sol";
import { ERC721URIStorage } from "oz-contracts/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import { ERC721Enumerable } from "oz-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import { HypercertMinter } from "../HypercertMinter.sol";

import { EIP712 } from "oz-contracts/contracts/utils/cryptography/draft-EIP712.sol";
import { ECDSA } from "oz-contracts/contracts/utils/cryptography/ECDSA.sol";

import { Strings } from "oz-contracts/contracts/utils/Strings.sol";

import { Ownable } from "oz-contracts/contracts/access/Ownable.sol";
import { CountersUpgradeable } from "oz-upgradeable/utils/CountersUpgradeable.sol";

import { Errors } from "../libs/Errors.sol";

/// @title A hyperboard NFT
/// @author Abhimanyu Shekhawat
/// @notice This is an NFT for representing various hyperboards
contract Hyperboard is ERC721, ERC721URIStorage, ERC721Enumerable, Ownable, EIP712 {
    using SafeERC20 for IERC20;
    string public subgraphEndpoint;
    string public baseUri;
    HypercertMinter public hypercertMinter;

    mapping(uint256 => uint256[]) private _allowListedCertsMapping;
    mapping(uint256 => uint256[]) public consentBasedCertsMapping;

    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter private _counter;

    /// @notice Emitted when new token is minted
    /// @param to Address thats recieving NFT.
    /// @param tokenId tokenId of the new mint.
    /// @param metadata of hyperboard.
    event Mint(address indexed to, uint256 indexed tokenId, string metadata);

    /// @notice Event is emitted when contract gets consent from a hypercert.
    /// @param tokenId Token Id of hyperboard.
    /// @param claimId ClaimId of a hypercert.
    /// @param owner owner of hypercert.
    event GotConsent(uint256 indexed tokenId, uint256 indexed claimId, address owner);

    /// @notice Emitted when ERC20 tokens are withdrawn.
    /// @param to address where tokens were sent to.
    /// @param tokenAddress Address  of token withdrawn.
    /// @param amount amount of tokems withdrawn.
    event WithdrawToken(address indexed to, address indexed tokenAddress, uint256 indexed amount);

    /// @notice Emitted when subgraph endpoint is updated.
    /// @param endpoint updated Subgraph endpoint.
    event SubgraphUpdated(string endpoint);

    /// @notice Emitted when base uri is updated.
    /// @param baseUri Updated baseuri.
    event BaseUriUpdated(string baseUri);

    /// @notice Emitted when hypercert address is updated
    /// @param hypercertMinter semifungible token.
    event HypercertMinterUpdated(HypercertMinter indexed hypercertMinter);

    /// @param name_ name of NFT.
    /// @param hypercertMinter_ hypercertToken address
    /// @param symbol_ NFT symbol
    /// @param subgraphEndpoint_ updateable subgraph endpoint
    /// @param baseUri_ base ipfs uri for NFT page.
    constructor(
        HypercertMinter hypercertMinter_,
        string memory name_,
        string memory symbol_,
        string memory subgraphEndpoint_,
        string memory baseUri_,
        string memory version
    ) ERC721(name_, symbol_) EIP712(name_, version) {
        if (address(hypercertMinter_) == address(0)) revert Errors.ZeroAddress();
        hypercertMinter = hypercertMinter_;
        emit HypercertMinterUpdated(hypercertMinter);

        subgraphEndpoint = subgraphEndpoint_;
        emit SubgraphUpdated(subgraphEndpoint);

        baseUri = baseUri_;
        emit BaseUriUpdated(baseUri);
    }

    /// @notice Mints a new Hyperboard.
    /// @param to The address to which the Hyperboard NFT will be minted.
    /// @param allowlistedClaimIds_ Claim IDs corresponding to allowlisted certificates.
    /// @return tokenId The ID of the minted NFT.
    function mint(
        address to,
        uint256[] memory allowlistedClaimIds_,
        string memory metadata_
    ) external returns (uint256 tokenId) {
        if (to == address(0)) revert Errors.ZeroAddress();

        tokenId = _counter.current();
        _mint(to, tokenId);
        _setTokenURI(tokenId, metadata_);
        _setAllowlist(tokenId, allowlistedClaimIds_);

        _counter.increment();
        emit Mint(to, tokenId, metadata_);

        return tokenId;
    }

    /// @notice gives consent from a hypercert to be part of Hyperboard
    /// @param tokenId_ tokenId of a hyperboard.
    /// @param claimId_ ClaimId of a hypercert.
    function consentForHyperboard(uint256 tokenId_, uint256 claimId_) external {
        _consentForHyperboard(tokenId_, claimId_, msg.sender);
    }

    /// @notice gives consent from a hypercert to be part of Hyperboard using signatures of the owner
    /// @param tokenId_ tokenId of a hyperboard.
    /// @param claimId_ ClaimId of a hypercert.
    /// @param signer Address of owner of hypercert.
    /// @param r r of signature of digest for consent.
    /// @param s s of signature of digest for consent.
    /// @param v v of signature of digest for consent.
    function consentForHyperboardWithSignature(
        uint256 tokenId_,
        uint256 claimId_,
        address signer,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(keccak256("ConsentForHyperBoard(uint256 tokenId_,uint256 claimId_)"), tokenId_, claimId_)
            )
        );
        address recoveredSigner = ECDSA.recover(digest, v, r, s);
        if (recoveredSigner != signer) revert Errors.InvalidSigner();
        _consentForHyperboard(tokenId_, claimId_, signer);
    }

    /// @notice gives digest that needs to be signed by owner to give consenst using signature.
    /// @param tokenId_ tokenId of a hyperboard.
    /// @param claimId_ ClaimId of a hypercert.
    function getDigestForConsent(uint256 tokenId_, uint256 claimId_) external returns (bytes32) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(keccak256("ConsentForHyperBoard(uint256 tokenId_,uint256 claimId_)"), tokenId_, claimId_)
            )
        );
        return digest;
    }

    /// @notice internal function that actually gives consent.
    /// @param tokenId_ tokenId of a hyperboard.
    /// @param claimId_ ClaimId of a hypercert.
    /// @param owner_ address of owner of hypercert.
    function _consentForHyperboard(uint256 tokenId_, uint256 claimId_, address owner_) internal {
        if (hypercertMinter.ownerOf(claimId_) != owner_) revert Errors.NotApprovedOrOwner();
        consentBasedCertsMapping[tokenId_].push(claimId_);
        emit GotConsent(tokenId_, claimId_, msg.sender);
    }

    /// @notice Updates the allowlisted certificates for an Hyperboard NFT.
    /// @param tokenId_ The ID of the NFT.
    /// @param allowlistedClaimIds_ Updated claim IDs corresponding to allowlisted certificates.
    /// @param metadata_ Updated metadata, to reflect new claimIds in the board.
    function updateHyperboad(
        uint256 tokenId_,
        uint256[] memory allowlistedClaimIds_,
        string memory metadata_
    ) external {
        if (ownerOf(tokenId_) != msg.sender) revert Errors.NotApprovedOrOwner();
        _setTokenURI(tokenId_, metadata_);
        _setAllowlist(tokenId_, allowlistedClaimIds_);
    }

    /// @notice Gets the allowlisted certificates for an NFT.
    /// @param tokenId The ID of the NFT.
    /// @return allowlistedCerts The array of allowlisted certificate addresses.
    function getAllowListedCerts(uint256 tokenId) external view returns (uint256[] memory) {
        return _allowListedCertsMapping[tokenId];
    }

    /// @dev Get URI of token, i.e. URL of NFT webpage
    /// @param tokenId id of the token to get URI for.
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return
            string.concat(
                baseUri,
                "?tokenId=",
                Strings.toString(tokenId),
                "&subgraph=",
                subgraphEndpoint,
                "&tokenURI=",
                ERC721URIStorage.tokenURI(tokenId)
            );
    }

    /// @dev checks if this contract supports specific interface.
    /// @param interfaceId interface ID that you want to check the contract against.
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Sets the subgraph endpoint for the hyperboards.
    /// @param endpoint_ The new subgraph endpoint.
    function setSubgraphEndpoint(string memory endpoint_) external onlyOwner {
        subgraphEndpoint = endpoint_;
        emit SubgraphUpdated(subgraphEndpoint);
    }

    /// @notice update the base URI
    /// @param baseUri_ The new 6551 registry address.
    function setBaseUri(string memory baseUri_) external onlyOwner {
        baseUri = baseUri_;
        emit BaseUriUpdated(baseUri);
    }

    /// @notice update the hypercert contract
    /// @param hypercertMinter_ The new minter address.
    function setHypercertContract(HypercertMinter hypercertMinter_) external onlyOwner {
        hypercertMinter_ = hypercertMinter;
        emit HypercertMinterUpdated(hypercertMinter_);
    }

    /// @notice Withdraws accidentally transferred ERC20 tokens from the contract to a specified account.
    /// @param token The ERC20 token contract address.
    /// @param amount The amount of tokens to withdraw.
    /// @param account The recipient account address.
    function withdrawErc20(IERC20 token, uint256 amount, address account) external onlyOwner {
        token.safeTransfer(account, amount);
        emit WithdrawToken(account, address(token), amount);
    }

    /// @notice Withdraws accidentally transferred Ether from the contract to a specified account.
    /// @param amount The amount of Ether to withdraw.
    /// @param account The recipient account address.
    function withdrawEther(uint256 amount, address payable account) external onlyOwner {
        (bool sent, ) = account.call{ value: amount }("");
        if (!sent) revert Errors.FailedToSendToken();
        emit WithdrawToken(account, address(0), amount);
    }

    /// @dev Sets the allowlisted certificates and their corresponding claim IDs for an NFT.
    /// @param tokenId The ID of the NFT.
    /// @param allowlistedClaimIds_ Claim IDs corresponding to allowlisted certificates.
    /// @dev This function is used internally to set the allowlist for a specific NFT.
    function _setAllowlist(uint256 tokenId, uint256[] memory allowlistedClaimIds_) internal {
        _allowListedCertsMapping[tokenId] = allowlistedClaimIds_;
    }

    /// @dev any condtion can be put into this to be checked before transefering tokens.
    /// @param from which accounts token needs to be tranferred.
    /// @param to who will be the recipient of token.
    /// @param tokenId token Id of token being transferred.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /// @dev internal function to burn the token
    /// @param tokenId Id of token that needs to be burned.
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }
}
