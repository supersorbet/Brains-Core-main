// SPDX-License-Identifier: kekware
pragma solidity ^0.8.23;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {BrainERC20} from "./BrainERC20.sol";
import {BrainsMetadata} from "./BrainMetadata.sol";

/// @title Brains NFT Contract
/// @notice This contract manages the creation, minting, and management of Brains NFTs and their associated ERC20 tokens
/// @dev Inherits from ERC721Enumerable, ReentrancyGuard, Ownable, and IERC721Receiver
contract Brains is ERC721Enumerable, ReentrancyGuard, Ownable, IERC721Receiver {
    using SafeTransferLib for address;
    using LibString for uint256;

    // Custom errors
    /// @notice Thrown when an unauthorized address attempts to perform an action
    error UnauthorizedAccess();

    /// @notice Thrown when the provided amount is insufficient for an operation
    /// @param provided The amount provided
    /// @param required The amount required
    error InsufficientAmount(uint256 provided, uint256 required);

    /// @notice Thrown when an invalid amount is provided for an operation
    /// @param amount The invalid amount
    error InvalidAmount(uint256 amount);

    /// @notice Thrown when minting would exceed the maximum supply
    /// @param current The current supply
    /// @param max The maximum allowed supply
    error MaxSupplyExceeded(uint256 current, uint256 max);

    /// @notice Thrown when attempting to unstake before the stake duration has passed
    /// @param remainingTime The time remaining until unstaking is allowed
    error StakeDurationNotMet(uint256 remainingTime);

    /// @notice Thrown when attempting to activate an already activated Brain NFT
    /// @param tokenId The ID of the Brain NFT
    error BrainAlreadyActivated(uint256 tokenId);

    /// @notice Thrown when the total contributions are insufficient for an operation
    /// @param total The total contributions
    /// @param required The required amount of contributions
    error InsufficientContributions(uint256 total, uint256 required);

    /// @notice Thrown when attempting to execute an already executed proposal
    error ProposalAlreadyExecuted();

    /// @notice Thrown when the voting threshold for a proposal is not met
    /// @param votes The number of votes received
    /// @param required The required number of votes
    error VotingThresholdNotMet(uint256 votes, uint256 required);

    /// @notice Thrown when attempting to withdraw votes when there are none to withdraw
    error NoVotesToWithdraw();

    /// @notice Thrown when attempting to update metadata for a Brain NFT with disabled updates
    /// @param tokenId The ID of the Brain NFT
    error MetadataUpdateDisabled(uint256 tokenId);

    /// @notice Thrown when attempting to perform an operation on a non-activated Brain NFT
    /// @param tokenId The ID of the non-activated Brain NFT
    error BrainTokenNotActivated(uint256 tokenId);

    /// @notice Thrown when a Brain operation fails
    /// @param code The error code indicating the type of failure
    error BrainOperationFailed(uint8 code);

    /// @notice Thrown when the creation of a clone contract fails
    error CloneCreationFailed();

    /// @notice Thrown when the initialization of an ERC20 token fails
    /// @param step The step at which the initialization failed
    error ERC20InitializationFailed(uint256 step);

    /// @notice Thrown when the user has insufficient Brain tokens for an operation
    /// @param balance The user's current balance
    /// @param required The required balance
    error InsufficientBrainTokens(uint256 balance, uint256 required);

    /// @notice Thrown when minting is not allowed
    error MintingNotAllowed();

    /// @notice Thrown when attempting to perform an operation on a non-existent token
    /// @param tokenId The ID of the non-existent token
    error TokenNotMinted(uint256 tokenId);

    /// @notice Thrown when an invalid Brain ID is provided
    error InvalidBrainId();

    /// @notice Thrown when an insufficient contributor share is provided
    error InsufficientContributorShare();
    /// @notice Thrown when the total shares don't add up to 100%
    error InvalidSharesTotal();

    /// @notice Struct to store metadata for a Brain NFT
    struct BrainMetadata {
        string name;
        string metadataUrl;
        string imageUrl;
    }

    /// @notice Struct to store information about a Brain's associated ERC20 token
    struct BrainERC20Info {
        uint256 brainId;
        address erc20Address;
        uint256 totalSupply;
        uint256 userBalance;
        uint256 userOwnershipPercentage;
    }

    /// @notice Struct to store information about a contributor
    struct ContributorInfo {
        uint256 totalContribution;
        uint256[] contributedBrains;
    }

    /// @notice Address of the metadata contract
    BrainsMetadata public metadataContract;
    /// @notice Address of the Brain ERC20 implementation contract
    address public immutable brainERC20Implementation;
    /// @notice Address of the Brain Credits token contract
    address public brainCreditAddress;
    /// @notice Address of the Pepecoin token contract
    address public pepecoinAddress;
    /// @notice Counter for token IDs
    uint256 public tokenCounter;
    /// @notice Array of available token IDs
    uint256[] private availableTokenIds;
    /// @notice Array of activated Brain IDs
    uint256[] public activatedBrainIds;

    /// @notice Constant for the number of tokens per NFT
    uint256 private constant TOKENS_PER_NFT = 1000 * 1e18;
    /// @notice Constant for the stake amount
    uint256 private constant STAKE_AMOUNT = 100000 * 1e18;
    /// @notice Constant for the stake duration
    uint256 private constant STAKE_DURATION = 90 days;
    /// @notice Constant for the maximum supply of NFTs
    uint256 public constant MAX_SUPPLY = 1024;
    /// @notice Constant for the proposal threshold
    uint256 public constant PROPOSAL_THRESHOLD = 250000 * 1e18; // 250,000 tokens

    /// @notice Mapping of contributor addresses to their ContributorInfo
    mapping(address => ContributorInfo) public contributorInfo;
    /// @notice Mapping of Brain IDs to contributor addresses and their contributions
    mapping(uint256 => mapping(address => uint256)) public contributors;
    /// @notice Mapping of Brain IDs to their associated ERC20 token addresses
    mapping(uint256 => address) public brainToERC20;
    /// @notice Mapping of addresses to their staked amounts
    mapping(address => uint256) public stakes;
    /// @notice Mapping of token IDs to their stake times
    mapping(uint256 => uint256) public tokenStakeTime;
    /// @notice Mapping of token IDs to their URIs
    mapping(uint256 => string) private _tokenURIs;
    /// @notice Mapping of Brain IDs to their index in the activatedBrainIds array
    mapping(uint256 => uint256) public activatedBrainIndex;
    /// @notice Mapping of Brain IDs to their list of contributors
    mapping(uint256 => address[]) public contributorList;
    /// @notice Mapping of Brain IDs to their total contributions
    mapping(uint256 => uint256) public brainTotalContributions;

    /// @notice Constructor for the OPBrains contract
    /// @param _brainERC20Implementation Address of the Brain ERC20 implementation contract
    /// @param _metadataContractAddress Address of the metadata contract
    constructor(
        address _brainERC20Implementation,
        address _metadataContractAddress
    ) ERC721("BasedAI Brains", "BRAINS") {
        _initializeOwner(msg.sender);
        tokenCounter = 0;
        metadataContract = BrainsMetadata(_metadataContractAddress);
        brainERC20Implementation = _brainERC20Implementation;
    }

    /// @notice Allows users to redeem Brain NFTs using Brain Credits
    /// @param amount The amount of Brain Credits to redeem
    function redeemBrain(uint256 amount) external nonReentrant {
        if (brainCreditAddress == address(0)) revert UnauthorizedAccess();
        if (amount < TOKENS_PER_NFT)
            revert InsufficientAmount(amount, TOKENS_PER_NFT);
        if (amount % TOKENS_PER_NFT != 0) revert InvalidAmount(amount);

        uint256 numNFTs = amount / TOKENS_PER_NFT;
        if (tokenCounter + numNFTs > MAX_SUPPLY)
            revert MaxSupplyExceeded(tokenCounter + numNFTs, MAX_SUPPLY);

        try
            IERC20(brainCreditAddress).transferFrom(
                msg.sender,
                address(this),
                amount
            )
        {
            for (uint256 i = 0; i < numNFTs; ) {
                uint256 tokenId = _getNextTokenId();
                _safeMint(msg.sender, tokenId);
                emit BrainMinted(tokenId, msg.sender);
                unchecked {
                    ++i;
                }
            }
        } catch {
            revert("Transfer failed");
        }
    }

    /// @notice Allows users to stake Pepecoin to mint Brain NFTs
    /// @param amount The amount of Pepecoin to stake
    function stakePepecoin(uint256 amount) external nonReentrant {
        if (pepecoinAddress == address(0)) revert UnauthorizedAccess();
        if (amount % STAKE_AMOUNT != 0) revert InvalidAmount(amount);

        uint256 numNFTs = amount / STAKE_AMOUNT;
        if (tokenCounter + numNFTs > MAX_SUPPLY)
            revert MaxSupplyExceeded(tokenCounter + numNFTs, MAX_SUPPLY);

        try
            IERC20(pepecoinAddress).transferFrom(
                msg.sender,
                address(this),
                amount
            )
        {
            stakes[msg.sender] += amount;
            IBrainCredits(brainCreditAddress).decreaseTotalSupply();

            for (uint256 i = 0; i < numNFTs; ) {
                uint256 tokenId = _getNextTokenId();
                _safeMint(msg.sender, tokenId);
                tokenStakeTime[tokenId] = block.timestamp;
                emit BrainMinted(tokenId, msg.sender);
                unchecked {
                    ++i;
                }
            }
        } catch {
            revert("Transfer failed");
        }
    }

    /// @notice Allows users to unstake Pepecoin and burn their Brain NFT
    /// @param tokenId The ID of the Brain NFT to unstake
    function unstakePepecoin(uint256 tokenId) external nonReentrant {
        if (ownerOf(tokenId) != msg.sender) revert UnauthorizedAccess();
        if (block.timestamp < tokenStakeTime[tokenId] + STAKE_DURATION)
            revert StakeDurationNotMet(
                (tokenStakeTime[tokenId] + STAKE_DURATION) - block.timestamp
            );
        if (stakes[msg.sender] < STAKE_AMOUNT)
            revert InsufficientAmount(stakes[msg.sender], STAKE_AMOUNT);

        stakes[msg.sender] -= STAKE_AMOUNT;
        pepecoinAddress.safeTransfer(msg.sender, STAKE_AMOUNT);
        _burn(tokenId);
        availableTokenIds.push(tokenId);

        IBrainCredits(brainCreditAddress).increaseTotalSupply();
    }

    /// @notice Activates a Brain NFT by deploying its associated ERC20 token
    /// @param tokenId The ID of the Brain NFT to activate
    function activateBrain(uint256 tokenId) external {
        if (ownerOf(tokenId) != msg.sender) revert BrainOperationFailed(1);
        if (brainToERC20[tokenId] != address(0)) revert BrainOperationFailed(2);

        address erc20Contract = _deployERC20(msg.sender, tokenId);
        brainToERC20[tokenId] = erc20Contract;
        emit BrainTokenActivated(tokenId, erc20Contract);
    }

    /// @notice Internal function to deploy an ERC20 token for a Brain NFT
    /// @param tokenOwner The owner of the Brain NFT
    /// @param tokenId The ID of the Brain NFT
    /// @return The address of the deployed ERC20 token contract
    function _deployERC20(
        address tokenOwner,
        uint256 tokenId
    ) internal returns (address) {
        address erc20Contract = Clones.clone(brainERC20Implementation);
        if (erc20Contract == address(0)) revert CloneCreationFailed();

        string memory name = string(
            abi.encodePacked("BRAIN TOKEN #", tokenId.toString())
        );
        string memory symbol = string(
            abi.encodePacked("B#", tokenId.toString())
        );
        uint256 initialSupply = 1000000 * 1e18;

        (bool success, ) = erc20Contract.call( //init de share
            abi.encodeWithSelector(
                IBrainERC20.initialize.selector,
                name,
                symbol,
                initialSupply,
                tokenOwner,
                address(this)
            )
        );
        if (!success) revert ERC20InitializationFailed(4);
        if (brainTotalContributions[tokenId] > 0) {
            address[] memory contributorAddresses = contributorList[tokenId];
            uint256[] memory shares = new uint256[](
                contributorAddresses.length
            );

            for (uint256 i = 0; i < contributorAddresses.length; i++) {
                shares[i] =
                    (contributors[tokenId][contributorAddresses[i]] *
                        initialSupply) /
                    TOKENS_PER_NFT;
            }

            IBrainERC20(erc20Contract).setContributorShares(
                contributorAddresses,
                shares
            );
        }

        return erc20Contract;
    }

    /// @notice Allows users to contribute Brain Credits towards minting a Brain NFT
    /// @param brainId The ID of the Brain NFT to contribute to
    /// @param amount The amount of Brain Credits to contribute
    function contributeBrainCredits(
        uint256 brainId,
        uint256 amount
    ) external nonReentrant {
        if (metadataContract.isBrainActivated(brainId))
            revert BrainAlreadyActivated(brainId);
        if (brainCreditAddress == address(0)) revert UnauthorizedAccess();
        if (!_exists(brainId)) revert InvalidBrainId();
        try
            IERC20(brainCreditAddress).transferFrom(
                msg.sender,
                address(this),
                amount
            )
        {
            if (contributors[brainId][msg.sender] == 0) {
                contributorList[brainId].push(msg.sender);
            }
            contributors[brainId][msg.sender] += amount;
            brainTotalContributions[brainId] += amount;
            contributorInfo[msg.sender].totalContribution += amount;
            contributorInfo[msg.sender].contributedBrains.push(brainId);
            emit ContributionReceived(msg.sender, amount, brainId);
        } catch {
            revert("Transfer failed");
        }
    }

    /// @notice Mints a Brain NFT collectively when enough contributions have been made
    /// @param brainId The ID of the Brain NFT to mint
    function collectiveMint(uint256 brainId) external nonReentrant {
        if (metadataContract.isBrainActivated(brainId))
            revert BrainAlreadyActivated(brainId);
        if (brainTotalContributions[brainId] < TOKENS_PER_NFT)
            revert InsufficientContributions(
                brainTotalContributions[brainId],
                TOKENS_PER_NFT
            );
        if (tokenCounter >= MAX_SUPPLY)
            revert MaxSupplyExceeded(tokenCounter, MAX_SUPPLY);

        uint256 tokenId = _getNextTokenId();
        emit BrainMinted(tokenId, address(this));
        _safeMint(address(this), tokenId);

        address[] memory contributorAddresses = contributorList[brainId];
        uint256[] memory shares = new uint256[](contributorAddresses.length);
        uint256 totalShares = 0;
        uint256 totalUsedContributions = 0;

        for (uint256 i = 0; i < contributorAddresses.length; i++) {
            shares[i] =
                (contributors[brainId][contributorAddresses[i]] * 1e18) /
                TOKENS_PER_NFT;
            totalShares += shares[i];
            totalUsedContributions += contributors[brainId][
                contributorAddresses[i]
            ];
        }

        if (totalShares != 1e18) revert InvalidSharesTotal();

        address erc20Contract = _deployERC20(address(this), tokenId);
        brainToERC20[tokenId] = erc20Contract;

        for (uint256 i = 0; i < contributorAddresses.length; i++) {
            if (shares[i] > 0) {
                IBrainERC20(erc20Contract).transfer(
                    contributorAddresses[i],
                    shares[i]
                );
            }
        }

        emit BrainTokenActivated(tokenId, erc20Contract);
        _adjustContributionsAfterMint(brainId, totalUsedContributions);
    }

    /// @notice Internal function to adjust contributions after a successful mint
    /// @param brainId The ID of the Brain NFT
    /// @param usedContributions The amount of contributions used for minting
    function _adjustContributionsAfterMint(
        uint256 brainId,
        uint256 usedContributions
    ) internal {
        brainTotalContributions[brainId] -= usedContributions;
        for (uint256 i = 0; i < contributorList[brainId].length; i++) {
            address contributor = contributorList[brainId][i];
            contributorInfo[contributor].totalContribution -= contributors[
                brainId
            ][contributor];
            contributors[brainId][contributor] = 0;
        }
        delete contributorList[brainId];
    }

    /// @notice Allows the owner to mint Brain NFTs for the labs
    /// @param tokenIds An array of token IDs to mint
    function mintLabsBrain(uint256[] calldata tokenIds) public onlyOwner {
        if (pepecoinAddress != address(0)) revert MintingNotAllowed();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (tokenId >= MAX_SUPPLY)
                revert MaxSupplyExceeded(tokenId, MAX_SUPPLY);

            emit BrainMinted(tokenId, msg.sender);
            IBrainCredits(brainCreditAddress).decreaseTotalSupply();
            _safeMint(msg.sender, tokenId);

            if (tokenId >= tokenCounter) {
                tokenCounter = tokenId + 1;
            }
        }
    }

    /// @notice Retrieves user data including owned tokens, linked ERC20s, staked amount, and total contribution
    /// @param user The address of the user
    /// @return ownedTokenIds An array of token IDs owned by the user
    /// @return linkedERC20s An array of ERC20 addresses linked to the owned tokens
    /// @return stakedAmount The total amount staked by the user
    /// @return contributionAmount The total contribution made by the user
    function getUserData(
        address user
    )
        external
        view
        returns (
            uint256[] memory ownedTokenIds,
            address[] memory linkedERC20s,
            uint256 stakedAmount,
            uint256 contributionAmount
        )
    {
        uint256 balance = balanceOf(user);
        ownedTokenIds = new uint256[](balance);
        linkedERC20s = new address[](balance);

        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(user, i);
            ownedTokenIds[i] = tokenId;
            linkedERC20s[i] = brainToERC20[tokenId];
        }

        stakedAmount = stakes[user];
        contributionAmount = contributorInfo[user].totalContribution;
    }

    /// @notice Proposes a metadata change for a Brain NFT
    /// @param tokenId The ID of the Brain NFT
    /// @param name The proposed new name
    /// @param metadataUrl The proposed new metadata URL
    /// @param imageUrl The proposed new image URL
    function proposeMetadataChange(
        uint256 tokenId,
        string memory name,
        string memory metadataUrl,
        string memory imageUrl
    ) external {
        metadataContract.proposeMetadataChange(
            tokenId,
            name,
            metadataUrl,
            imageUrl
        );
    }

    /// @notice Internal function to execute a metadata change proposal
    /// @param tokenId The ID of the Brain NFT
    /// @param proposalId The ID of the proposal to execute
    function _executeProposal(uint256 tokenId, uint256 proposalId) internal {
        metadataContract.executeProposal(tokenId, proposalId);
    }

    /// @notice Allows users to vote on a metadata change proposal
    /// @param tokenId The ID of the Brain NFT
    /// @param proposalId The ID of the proposal
    /// @param amount The amount of tokens to use for voting
    function voteOnProposal(
        uint256 tokenId,
        uint256 proposalId,
        uint256 amount
    ) external {
        metadataContract.voteOnProposal(tokenId, proposalId, amount);
    }

    /// @notice Allows users to withdraw their votes from a proposal
    /// @param tokenId The ID of the Brain NFT
    /// @param proposalId The ID of the proposal
    function withdrawVotes(uint256 tokenId, uint256 proposalId) external {
        metadataContract.withdrawVotes(tokenId, proposalId);
    }

    /// @notice Updates the metadata for a Brain NFT
    /// @param tokenId The ID of the Brain NFT
    /// @param name The new name
    /// @param metadataUrl The new metadata URL
    /// @param imageUrl The new image URL
    function updateBrainMetadata(
        uint256 tokenId,
        string memory name,
        string memory metadataUrl,
        string memory imageUrl
    ) external {
        if (ownerOf(tokenId) != msg.sender) revert UnauthorizedAccess();
        metadataContract.updateBrainMetadata(
            tokenId,
            name,
            metadataUrl,
            imageUrl
        );
    }

    /// @notice Internal function to get the next available token ID
    /// @return The next available token ID
    function _getNextTokenId() private returns (uint256) {
        if (availableTokenIds.length > 0) {
            uint256 tokenId = availableTokenIds[availableTokenIds.length - 1];
            availableTokenIds.pop();
            return tokenId;
        } else {
            uint256 tokenId = tokenCounter;
            if (tokenId == 47) {
                tokenId = 48;
                tokenCounter = 49;
            } else {
                tokenCounter++;
            }
            return tokenId;
        }
    }

    /// @notice Processes multiple function calls in a single transaction
    /// @param data Array of encoded function calls
    /// @return results Array of return data from each call
    function multicall(
        bytes[] calldata data
    ) external view returns (bytes[] memory results) {
        assembly {
            // Allocate memory for the results array
            results := mload(0x40)
            let resultsLength := mload(data)
            mstore(results, resultsLength) 

            let memPtr := add(results, 0x20)
            let endPtr := add(memPtr, mul(resultsLength, 0x20))
            mstore(0x40, endPtr) 
            // For each call in data array
            for { let i := 0 } lt(i, resultsLength) { i := add(i, 1) } {
                // Get current call data
                let callDataOffset := calldataload(add(add(data.offset, 0x20), mul(i, 0x20)))
                let callDataLength := calldataload(add(data.offset, callDataOffset))
                let success := 0
                let resultOffset := mload(0x40)

                success := staticcall(
                    gas(),
                    address(),
                    add(add(data.offset, callDataOffset), 0x20),
                    callDataLength,
                    add(resultOffset, 0x20),
                    0x2000
                )
                if iszero(success) {
                    mstore(0x00, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                    mstore(0x04, 0x0000002000000000000000000000000000000000000000000000000000000000)
                    mstore(0x24, 0x0000001484756c746963616c6c3a2063616c6c206661696c65640000000000)
                    revert(0x00, 0x44)
                }
                // Store result
                let returnSize := returndatasize()
                mstore(resultOffset, returnSize)
                returndatacopy(add(resultOffset, 0x20), 0, returnSize)

                // Store pointer in results array
                mstore(add(memPtr, mul(i, 0x20)), resultOffset)

                // Update free memory pointer
                mstore(0x40, add(add(resultOffset, 0x20), returnSize))
            }
        }
    }

    /// @notice Gets the time remaining until a staked token can be withdrawn
    /// @param tokenId The ID of the Brain NFT
    /// @return The time remaining in seconds
    function getTimeUntilWithdrawal(
        uint256 tokenId
    ) external view returns (uint256) {
        if (ownerOf(tokenId) != msg.sender) revert UnauthorizedAccess();
        uint256 stakeEndTime = tokenStakeTime[tokenId] + STAKE_DURATION;
        return
            stakeEndTime > block.timestamp ? stakeEndTime - block.timestamp : 0;
    }

    /// @notice Gets the staked amount for a given address
    /// @param staker The address of the staker
    /// @return The amount staked by the given address
    function getStakedAmount(address staker) external view returns (uint256) {
        return stakes[staker];
    }

    /// @notice Override of the ERC721Enumerable totalSupply function
    /// @return The total number of tokens minted
    function totalSupply()
        public
        view
        override(ERC721Enumerable)
        returns (uint256)
    {
        return tokenCounter;
    }

    /// @notice Gets the token URI for a given token ID
    /// @param tokenId The ID of the token
    /// @return The token URI
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (!_exists(tokenId)) revert TokenNotMinted(tokenId);

        BrainsMetadata.BrainMetadata memory metadata = metadataContract
            .getTokenMetadata(tokenId);
        if (bytes(metadata.metadataUrl).length > 0) {
            return metadata.metadataUrl;
        }

        return
            "https://ordinals.com/content/f4be79518ebb0283ed37012b42152dedc2bdfe2e7a89267c7448ab36e02bf99ci0";
    }

    /// @notice Toggles the blocking of a Brain NFT's URI
    /// @param tokenId The ID of the Brain NFT
    function toggleBlockBrainUri(uint256 tokenId) external onlyOwner {
        metadataContract.toggleBlockBrainUri(tokenId);
    }

    /// @notice Sets the token URI for a given token ID
    /// @param tokenId The ID of the token
    /// @param _tokenURI The new token URI
    function setTokenURI(uint256 tokenId, string memory _tokenURI) external {
        if (ownerOf(tokenId) != msg.sender) revert UnauthorizedAccess();
        if (!_exists(tokenId)) revert TokenNotMinted(tokenId);
        if (metadataContract.isTokenURIBlocked(tokenId))
            revert MetadataUpdateDisabled(tokenId);
        _tokenURIs[tokenId] = _tokenURI;
    }

    /// @notice Checks if a token exists
    /// @param tokenId The ID of the token to check
    /// @return bool indicating if the token exists
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /// @notice Sets the Brain Credits contract address
    /// @param _brainCreditAddress The address of the Brain Credits contract
    function setBrainCredits(address _brainCreditAddress) external onlyOwner {
        brainCreditAddress = _brainCreditAddress;
    }

    /// @notice Sets the Pepecoin contract address
    /// @param _pepecoinAddress The address of the Pepecoin contract
    function setPepecoin(address _pepecoinAddress) external onlyOwner {
        pepecoinAddress = _pepecoinAddress;
    }

    /// @notice Sets the metadata contract address
    /// @param _metadataContract The address of the metadata contract
    function setMetadataContract(address _metadataContract) external onlyOwner {
        metadataContract = BrainsMetadata(_metadataContract);
    }

    /// @notice Gets the user's share of a specific Brain NFT
    /// @param brainId The ID of the Brain NFT
    /// @param user The address of the user
    /// @return contributionAmount The amount contributed by the user
    /// @return shareAmount The amount of ERC20 tokens owned by the user
    /// @return sharePercentage The percentage of ownership
    function getUserBrainShare(
        uint256 brainId,
        address user
    )
        external
        view
        returns (
            uint256 contributionAmount,
            uint256 shareAmount,
            uint256 sharePercentage
        )
    {
        if (!_exists(brainId)) revert InvalidBrainId();
        address erc20Address = metadataContract.getBrainToERC20(brainId);

        contributionAmount = contributors[brainId][user];

        IBrainERC20 brainERC20 = IBrainERC20(erc20Address);
        shareAmount = brainERC20.balanceOf(user);

        uint256 brainTotalSupply = brainERC20.totalSupply();
        sharePercentage = brainTotalSupply > 0
            ? ((shareAmount * 1e18) / brainTotalSupply)
            : 0;
    }

    /// @notice Checks if a Brain NFT is activated
    /// @param brainId The ID of the Brain NFT
    /// @return bool indicating if the Brain is activated
    function isBrainActivated(uint256 brainId) public view returns (bool) {
        return metadataContract.getBrainToERC20(brainId) != address(0);
    }

    /// @notice Gets the ERC20 token address associated with a Brain NFT
    /// @param tokenId The ID of the Brain NFT
    /// @return The address of the associated ERC20 token
    function getBrainERC20(uint256 tokenId) public view returns (address) {
        return metadataContract.getBrainToERC20(tokenId);
    }

    /// @notice Gets the activated Brain NFTs owned by a user
    /// @param user The address of the user
    /// @return An array of activated Brain NFT IDs owned by the user
    function getUserActivatedBrains(
        address user
    ) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(user);
        uint256[] memory activatedBrains = new uint256[](balance);
        uint256 activatedCount = 0;

        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(user, i);
            if (isBrainActivated(tokenId)) {
                activatedBrains[activatedCount] = tokenId;
                activatedCount++;
            }
        }
        assembly {
            mstore(activatedBrains, activatedCount)
        }

        return activatedBrains;
    }

    /// @notice Gets the ERC20 token information for all Brain NFTs owned by a user
    /// @param user The address of the user
    /// @return An array of BrainERC20Info structs
    function getUserBrainERC20Info(
        address user
    ) external view returns (BrainERC20Info[] memory) {
        uint256 userBrainCount = balanceOf(user);
        BrainERC20Info[] memory brainInfos = new BrainERC20Info[](
            userBrainCount
        );

        for (uint256 i = 0; i < userBrainCount; i++) {
            uint256 brainId = tokenOfOwnerByIndex(user, i);
            address erc20Address = metadataContract.getBrainToERC20(brainId);

            if (erc20Address != address(0)) {
                IBrainERC20 brainToken = IBrainERC20(erc20Address);
                uint256 tokenTotalSupply = brainToken.totalSupply();
                uint256 userBalance = brainToken.balanceOf(user);
                uint256 ownershipPercentage = tokenTotalSupply > 0
                    ? ((userBalance * 1e18) / tokenTotalSupply)
                    : 0;

                brainInfos[i] = BrainERC20Info({
                    brainId: brainId,
                    erc20Address: erc20Address,
                    totalSupply: tokenTotalSupply,
                    userBalance: userBalance,
                    userOwnershipPercentage: ownershipPercentage
                });
            }
        }

        return brainInfos;
    }

    /// @notice Gets the Brain NFTs a user has contributed to
    /// @param user The address of the user
    /// @return brainIds An array of Brain NFT IDs the user has contributed to
    /// @return contributions An array of contribution amounts
    /// @return ownershipPercentages An array of ownership percentages
    function getUserContributedBrains(
        address user
    )
        external
        view
        returns (
            uint256[] memory brainIds,
            uint256[] memory contributions,
            uint256[] memory ownershipPercentages
        )
    {
        uint256[] memory contributedBrains = contributorInfo[user]
            .contributedBrains;
        uint256 contributedCount = contributedBrains.length;

        brainIds = new uint256[](contributedCount);
        contributions = new uint256[](contributedCount);
        ownershipPercentages = new uint256[](contributedCount);

        for (uint256 i = 0; i < contributedCount; i++) {
            uint256 brainId = contributedBrains[i];
            brainIds[i] = brainId;
            contributions[i] = contributors[brainId][user];

            address erc20Address = metadataContract.getBrainToERC20(brainId);
            if (erc20Address != address(0)) {
                IBrainERC20 brainToken = IBrainERC20(erc20Address);
                uint256 tokenTotalSupply = brainToken.totalSupply();
                uint256 userBalance = brainToken.balanceOf(user);
                ownershipPercentages[i] = tokenTotalSupply > 0
                    ? ((userBalance * 1e18) / tokenTotalSupply)
                    : 0;
            }
        }
    }

    /// @notice Gets the progress of a collective mint for a specific Brain NFT
    /// @param brainId The ID of the Brain NFT
    /// @return totalContributions The total amount of contributions
    /// @return contributorCount The number of contributors
    /// @return topContributors An array of the top 10 contributors' addresses
    /// @return topContributions An array of the top 10 contributors' contribution amounts
    function getCollectiveMintProgress(
        uint256 brainId
    )
        external
        view
        returns (
            uint256 totalContributions,
            uint256 contributorCount,
            address[] memory topContributors,
            uint256[] memory topContributions
        )
    {
        totalContributions = brainTotalContributions[brainId];
        address[] memory allContributors = contributorList[brainId];
        contributorCount = allContributors.length;

        uint256 topCount = contributorCount > 10 ? 10 : contributorCount;
        topContributors = new address[](topCount);
        topContributions = new uint256[](topCount);

        for (uint256 i = 0; i < contributorCount; i++) {
            address contributor = allContributors[i];
            uint256 contribution = contributors[brainId][contributor];

            for (uint256 j = 0; j < topCount; j++) {
                if (contribution > topContributions[j]) {
                    for (uint256 k = topCount - 1; k > j; k--) {
                        topContributors[k] = topContributors[k - 1];
                        topContributions[k] = topContributions[k - 1];
                    }
                    topContributors[j] = contributor;
                    topContributions[j] = contribution;
                    break;
                }
            }
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // Events
    /// @notice Emitted when a new Brain NFT is minted
    /// @param nftId The ID of the minted Brain NFT
    /// @param brainFather The address of the minter
    event BrainMinted(uint256 indexed nftId, address indexed brainFather);

    /// @notice Emitted when a Brain NFT's associated ERC20 token is activated
    /// @param nftId The ID of the Brain NFT
    /// @param brainTokenAddress The address of the associated ERC20 token
    event BrainTokenActivated(
        uint256 indexed nftId,
        address indexed brainTokenAddress
    );

    /// @notice Emitted when a contribution is received for a Brain NFT
    /// @param contributor The address of the contributor
    /// @param amount The amount contributed
    /// @param brainId The ID of the Brain NFT
    event ContributionReceived(
        address indexed contributor,
        uint256 amount,
        uint256 indexed brainId
    );

    /// @notice Emitted when a Brain NFT's metadata is updated
    /// @param tokenId The ID of the Brain NFT
    /// @param name The new name
    /// @param metadataUrl The new metadata URL
    /// @param imageUrl The new image URL
    event BrainMetadataUpdated(
        uint256 indexed tokenId,
        string name,
        string metadataUrl,
        string imageUrl
    );

    /// @notice Emitted when a Brain NFT is transferred
    /// @param tokenId The ID of the Brain NFT
    /// @param from The address of the previous owner
    /// @param to The address of the new owner
    /// @param timestamp The timestamp of the transfer
    event BrainTransferred(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to,
        uint256 timestamp
    );

    /// @notice Emitted when a new metadata change is proposed
    /// @param tokenId The ID of the Brain NFT
    /// @param proposalId The ID of the proposal
    /// @param name The proposed new name
    /// @param metadataUrl The proposed new metadata URL
    /// @param imageUrl The proposed new image URL
    event MetadataChangeProposed(
        uint256 indexed tokenId,
        uint256 proposalId,
        string name,
        string metadataUrl,
        string imageUrl
    );

    /// @notice Emitted when a vote is cast on a metadata change proposal
    /// @param tokenId The ID of the Brain NFT
    /// @param proposalId The ID of the proposal
    /// @param voter The address of the voter
    /// @param amount The amount of tokens used for voting
    event VoteCast(
        uint256 indexed tokenId,
        uint256 proposalId,
        address indexed voter,
        uint256 amount
    );

    /// @notice Emitted when a Brain NFT is associated with an ERC20 token
    /// @param tokenId The ID of the Brain NFT
    /// @param erc20Address The address of the associated ERC20 token
    event BrainERC20Associated(
        uint256 indexed tokenId,
        address indexed erc20Address
    );

    /// @notice Emitted when a new ERC20 token is deployed for a Brain NFT
    /// @param tokenId The ID of the Brain NFT
    /// @param erc20Address The address of the deployed ERC20 token
    /// @param owner The address of the owner
    event BrainERC20Deployed(
        uint256 indexed tokenId,
        address indexed erc20Address,
        address indexed owner
    );

    /// @notice Gets the number of tokens per NFT
    /// @return The number of tokens per NFT
    function TOKENS_PER_NFT() external pure returns (uint256) {
        return TOKENS_PER_NFT;
    }
}

/// @title IBrainCredits Interface
/// @notice Interface for the Brain Credits contract
interface IBrainCredits {
    /// @notice Decreases the total supply of Brain Credits
    function decreaseTotalSupply() external;

    /// @notice Increases the total supply of Brain Credits
    function increaseTotalSupply() external;
}

/// @title IBrainERC20 Interface
/// @notice Interface for the Brain ERC20 token contract
interface IBrainERC20 {
    /// @notice Initializes the Brain ERC20 token
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param initialSupply The initial supply of tokens
    /// @param owner The address of the token owner
    function initialize(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address owner,
        address brainContract
    ) external;

    /// @notice Transfers tokens to a recipient
    /// @param to The address of the recipient
    /// @param amount The amount of tokens to transfer
    /// @return A boolean indicating whether the transfer was successful
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Gets the balance of an account
    /// @param account The address of the account
    /// @return The balance of the account
    function balanceOf(address account) external view returns (uint256);

    /// @notice Gets the total supply of tokens
    /// @return The total supply of tokens
    function totalSupply() external view returns (uint256);

    /// @notice Sets the contributor shares for a Brain NFT
    /// @param contributors An array of contributor addresses
    /// @param shares An array of contributor shares
    function setContributorShares(
        address[] calldata contributors,
        uint256[] calldata shares
    ) external;

    /// @notice Gets the contributor shares for a Brain NFT
    /// @param contributor The address of the contributor
    /// @return The contributor shares
    function contributorShares(
        address contributor
    ) external view returns (uint256);

    /// @notice Gets the total contributor shares for a Brain NFT
    /// @return The total contributor shares
    function totalContributorShares() external view returns (uint256);
}

/// @title IBrainMetadata Interface
/// @notice Interface for the Brain Metadata contract
interface IBrainMetadata {
    /// @notice Sets the Brain NFT to ERC20 token association
    /// @param tokenId The ID of the Brain NFT
    /// @param erc20Address The address of the associated ERC20 token
    function setBrainToERC20(uint256 tokenId, address erc20Address) external;

    /// @notice Checks if a Brain NFT is activated
    /// @param tokenId The ID of the Brain NFT
    /// @return bool indicating if the Brain is activated
    function isBrainActivated(uint256 tokenId) external view returns (bool);

    /// @notice Gets the ERC20 token address associated with a Brain NFT
    /// @param tokenId The ID of the Brain NFT
    /// @return The address of the associated ERC20 token
    function getBrainToERC20(uint256 tokenId) external view returns (address);
}
