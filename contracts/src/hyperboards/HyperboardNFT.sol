// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
import { ERC721URIStorageUpgradeable } from "oz-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import { IERC20Upgradeable } from "oz-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { OwnableUpgradeable } from "oz-upgradeable/access/OwnableUpgradeable.sol";
import { CountersUpgradeable } from "oz-upgradeable/utils/CountersUpgradeable.sol";
import { Errors } from "../libs/errors.sol";
import { IERC6551Registry } from "../interfaces/IERC6551Registry.sol";

/// @title A hyperboard NFT
/// @author Abhimanyu Shekhawat
/// @notice This is an NFT for representing various hyperboards
contract Hyperboard is ERC721URIStorageUpgradeable, OwnableUpgradeable {
    string public subgraphEndpoint;
    string public baseUri;
    address public walletImpl;
    IERC6551Registry public erc6551Registry;

    mapping(uint256 => AllowlistedCerts) private _allowListedCertsMapping;
    mapping(uint256 => address) public tokenWalletMapping;
    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter private _counter;

    struct AllowlistedCerts {
        address[] allowlistedCerts;
        mapping(address => uint256[]) claimIds;
    }

    /// @param name_ name of NFT.
    /// @param symbol_ NFT symbol
    /// @param subgraphEndpoint_ updateable subgraph endpoint
    /// @param baseUri_ base ipfs uri for NFT page.
    /// @param walletImpl_ wallet implementation address
    /// @param erc6551Registry_ 6551 registry for registring wallet.
    constructor(
        string memory name_,
        string memory symbol_,
        string memory subgraphEndpoint_,
        string memory baseUri_,
        address walletImpl_,
        IERC6551Registry erc6551Registry_
    ) {
        if (walletImpl == address(0)) revert Errors.ZeroAddress();
        if (address(erc6551Registry) == address(0)) revert Errors.ZeroAddress();
        walletImpl = walletImpl_;
        erc6551Registry = erc6551Registry_;
        __ERC721_init(name_, symbol_);
        subgraphEndpoint = subgraphEndpoint_;
        baseUri = baseUri_;
    }

    /// @notice Mints a new Hyperboard.
    /// @param to The address to which the Hyperboard NFT will be minted.
    /// @param allowlistedCertsAddress_ Addresses of allowlisted certificates.
    /// @param allowlistedClaimIds_ Claim IDs corresponding to allowlisted certificates.
    /// @param salt Salt value for wallet creation.
    /// @return tokenId The ID of the minted NFT.
    function mint(
        address to,
        address[] memory allowlistedCertsAddress_,
        uint256[][] memory allowlistedClaimIds_,
        uint256 salt
    ) external returns (uint256 tokenId) {
        if (allowlistedCertsAddress_.length != allowlistedClaimIds_.length) revert Errors.ArrayLengthMismatch();
        if (to == address(0)) revert Errors.ZeroAddress();
        tokenId = _counter.current();
        _mint(to, tokenId);
        _setAllowlist(tokenId, allowlistedCertsAddress_, allowlistedClaimIds_);
        tokenWalletMapping[tokenId] = erc6551Registry.createAccount(
            walletImpl,
            block.chainid,
            address(this),
            tokenId,
            salt,
            bytes("")
        );
        _counter.increment();
        return tokenId;
    }

    /// @notice Updates the allowlisted certificates for an Hyperboard NFT.
    /// @param tokenId The ID of the NFT.
    /// @param allowlistedCertsAddress_ Addresses of updated allowlisted certificates.
    /// @param allowlistedClaimIds_ Updated claim IDs corresponding to allowlisted certificates.
    function updateAllowListedCerts(
        uint256 tokenId,
        address[] memory allowlistedCertsAddress_,
        uint256[][] memory allowlistedClaimIds_
    ) external {
        if (ownerOf(tokenId) != msg.sender) revert Errors.NotOwner();
        _setAllowlist(tokenId, allowlistedCertsAddress_, allowlistedClaimIds_);
    }

    /// @notice Gets the allowlisted certificates for an NFT.
    /// @param tokenId The ID of the NFT.
    /// @return allowlistedCerts The array of allowlisted certificate addresses.
    function getAllowListedCerts(uint256 tokenId) external view returns (address[] memory) {
        return _allowListedCertsMapping[tokenId].allowlistedCerts;
    }

    /// @notice Gets the allowlisted claim IDs for a specific certificate and Hyperboard NFT.
    /// @param tokenId The ID of the Hyperboard NFT.
    /// @param hypercertAddress The address of the hypercert certificate.
    /// @return claimIds The array of allowlisted claim IDs.
    function getAllowListedClaimIds(
        uint256 tokenId,
        address hypercertAddress
    ) external view returns (uint256[] memory) {
        return _allowListedCertsMapping[tokenId].claimIds[hypercertAddress];
    }

    /// @notice Sets the subgraph endpoint for the hyperboards.
    /// @param endpoint_ The new subgraph endpoint.
    function setSubgraphEndpoint(string memory endpoint_) external onlyOwner {
        subgraphEndpoint = endpoint_;
    }

    /// @notice Sets the wallet implementation address.
    /// @param walletImpl_ The new wallet implementation address.
    function setWalletImpl(address walletImpl_) external onlyOwner {
        walletImpl = walletImpl_;
    }

    /// @notice Sets the 6551 registry for registering wallets.
    /// @param erc6551Registry_ The new 6551 registry address.
    function setErc6551Registry(IERC6551Registry erc6551Registry_) external onlyOwner {
        erc6551Registry = erc6551Registry_;
    }

    /// @notice Withdraws accidentally transferred ERC20 tokens from the contract to a specified account.
    /// @param token The ERC20 token contract address.
    /// @param amount The amount of tokens to withdraw.
    /// @param account The recipient account address.
    function withdrawErc20(IERC20Upgradeable token, uint256 amount, address account) external onlyOwner {
        token.transfer(account, amount);
    }

    /// @notice Withdraws accidentally transferred Ether from the contract to a specified account.
    /// @param amount The amount of Ether to withdraw.
    /// @param account The recipient account address.
    function withdrawEther(uint256 amount, address account) external onlyOwner {
        (bool sent, ) = account.call{ value: amount }("");
        if (!sent) revert Errors.FailedToSendEther();
    }

    /// @dev Sets the allowlisted certificates and their corresponding claim IDs for an NFT.
    /// @param tokenId The ID of the NFT.
    /// @param allowlistedCertsAddress_ Addresses of allowlisted certificates.
    /// @param allowlistedClaimIds_ Claim IDs corresponding to allowlisted certificates.
    /// @dev This function is used internally to set the allowlist for a specific NFT.
    function _setAllowlist(
        uint256 tokenId,
        address[] memory allowlistedCertsAddress_,
        uint256[][] memory allowlistedClaimIds_
    ) internal {
        if (allowlistedCertsAddress_.length != allowlistedClaimIds_.length) revert Errors.ArrayLengthMismatch();
        AllowlistedCerts storage allowListedCerts = _allowListedCertsMapping[tokenId];
        allowListedCerts.allowlistedCerts = allowlistedCertsAddress_;
        for (uint256 i = 0; i < allowlistedCertsAddress_.length; i++) {
            _allowListedCertsMapping[_counter.current()].claimIds[allowlistedCertsAddress_[i]] = allowlistedClaimIds_[
                i
            ];
        }
    }
}
