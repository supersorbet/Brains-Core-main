// SPDX-License-Identifier: kekware
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";

/// @title BrainsMetadata
/// @notice This contract manages metadata for brain tokens, allowing for proposals and voting on metadata changes.
/// @dev Implements proposal creation, voting, and execution mechanisms for updating brain token metadata.
contract BrainsMetadata is ReentrancyGuard, Ownable {
    using SafeTransferLib for address;

    /// @notice Thrown when an unauthorized address attempts to perform a restricted action
    error UnauthorizedAccess();
    /// @notice Thrown when trying to execute a proposal that has already been executed
    error ProposalAlreadyExecuted();
    /// @notice Thrown when a proposal doesn't meet the required voting threshold
    /// @param votes The current number of votes for the proposal
    /// @param required The required number of votes to pass the proposal
    error VotingThresholdNotMet(uint256 votes, uint256 required);
    /// @notice Thrown when a user tries to withdraw votes but has none locked
    error NoVotesToWithdraw();
    /// @notice Thrown when attempting to update metadata for a blocked token
    /// @param tokenId The ID of the blocked token
    error MetadataUpdateDisabled(uint256 tokenId);
    /// @notice Thrown when trying to interact with a brain token that hasn't been activated
    /// @param tokenId The ID of the non-activated token
    error BrainTokenNotActivated(uint256 tokenId);
    /// @notice Thrown when a user doesn't have enough brain tokens to perform an action
    /// @param balance The user's current balance
    /// @param required The required balance to perform the action
    error InsufficientBrainTokens(uint256 balance, uint256 required);
    /// @notice Thrown when trying to set an invalid ERC20 address for a brain token
    error InvalidERC20Address();
    /// @notice Thrown when trying to activate an already activated brain token
    /// @param tokenId The ID of the already activated token
    error BrainAlreadyActivated(uint256 tokenId);
    /// @notice Thrown when trying to interact with a non-existent proposal
    error ProposalDoesNotExist();
    /// @notice Thrown when a token transfer fails
    error TransferFailed();
    /// @notice Thrown when a non-creator tries to cancel a proposal
    error NotProposalCreator();
    /// @notice Thrown when trying to set an invalid brain contract address
    error InvalidBrainContractAddress();
    /// @notice Thrown when trying to set an invalid voting period
    error InvalidVotingPeriod();
    /// @notice Thrown when a voting period has ended
    error VotingPeriodEnded();

    /// @notice Structure to hold metadata proposal details
    struct MetadataProposal {
        string name;
        string metadataUrl;
        string imageUrl;
        uint256 votesLocked;
        mapping(address => uint256) voterLocks;
        bool executed;
    }

    /// @notice Structure to hold brain metadata
    struct BrainMetadata {
        string name;
        string metadataUrl;
        string imageUrl;
    }

    /// @notice Minimum number of votes required for a proposal to pass
    uint256 public constant PROPOSAL_THRESHOLD = 250000 * 1e18; // 250k

    /// @notice Minimum number of brain tokens required to propose or vote
    uint256 public constant MIN_BRAIN_TOKENS = 1000 * 1e18;

    /// @notice Minimum voting period duration
    uint256 public constant MIN_VOTING_PERIOD = 1 days;

    /// @notice Maximum voting period duration
    uint256 public constant MAX_VOTING_PERIOD = 7 days;

    // Mappings
    /// @notice Stores metadata proposals for each token ID and proposal ID
    /// @dev Maps token ID => proposal ID => MetadataProposal
    mapping(uint256 => mapping(uint256 => MetadataProposal)) public metadataProposals;

    /// @notice Tracks the number of proposals for each token ID
    /// @dev Maps token ID => proposal count
    mapping(uint256 => uint256) public proposalCounter;

    /// @notice Stores the end time for each proposal
    /// @dev Maps token ID => proposal ID => end time
    mapping(uint256 => uint256) public proposalEndTime;

    /// @notice Stores the current metadata for each brain token
    /// @dev Maps token ID => BrainMetadata
    mapping(uint256 => BrainMetadata) public brainMetadata;

    /// @notice Tracks whether a brain token is activated
    /// @dev Maps token ID => activation status
    mapping(uint256 => bool) public isBrainActivated;

    /// @notice Tracks whether a token ID is blocked from metadata updates
    /// @dev Maps token ID => blocked status
    mapping(uint256 => bool) private _blockedTokenIds;

    /// @notice Maps brain token IDs to their corresponding ERC20 token addresses
    /// @dev Maps token ID => ERC20 address
    mapping(uint256 => address) public brainToERC20;

    /// @notice Stores the creator of each proposal
    /// @dev Maps token ID => proposal ID => creator address
    mapping(uint256 => mapping(uint256 => address)) public proposalCreators;

    /// @notice Stores the voting period for each token ID
    /// @dev Maps token ID => voting period duration
    mapping(uint256 => uint256) public tokenVotingPeriod;

    /// @notice Address of the brain contract
    address public brainContract;

    /// @notice Initializes the contract with the brain contract address
    /// @param _brainContract Address of the brain contract
    constructor(address _brainContract) {
        brainContract = _brainContract;
    }

    /// @notice Modifier to restrict access to only the brain contract
    modifier onlyBrainContract() {
        if (msg.sender != brainContract) revert UnauthorizedAccess();
        _;
    }

    /// @notice Proposes a metadata change for a brain token
    /// @param tokenId The ID of the brain token
    /// @param name The proposed new name
    /// @param metadataUrl The proposed new metadata URL
    /// @param imageUrl The proposed new image URL
    function proposeMetadataChange(uint256 tokenId, string memory name, string memory metadataUrl, string memory imageUrl) external nonReentrant {
        address erc20Address = brainToERC20[tokenId];
        if (erc20Address == address(0)) revert BrainTokenNotActivated(tokenId);
        if (IERC20(erc20Address).balanceOf(msg.sender) < MIN_BRAIN_TOKENS) revert InsufficientBrainTokens(IERC20(erc20Address).balanceOf(msg.sender), MIN_BRAIN_TOKENS);
        if (_blockedTokenIds[tokenId]) revert MetadataUpdateDisabled(tokenId);
        
        uint256 proposalId = proposalCounter[tokenId]++;
        MetadataProposal storage proposal = metadataProposals[tokenId][proposalId];
        
        proposal.name = name;
        proposal.metadataUrl = metadataUrl;
        proposal.imageUrl = imageUrl;
        proposal.votesLocked = 0;
        proposal.executed = false;
        
        proposalCreators[tokenId][proposalId] = msg.sender;
        
        uint256 votingPeriod = tokenVotingPeriod[tokenId];
        if (votingPeriod == 0) votingPeriod = MIN_VOTING_PERIOD;
        proposalEndTime[tokenId][proposalId] = block.timestamp + votingPeriod;
        
        emit MetadataChangeProposed(tokenId, proposalId, name, metadataUrl, imageUrl);
    }

    /// @notice Allows a user to vote on a metadata change proposal
    /// @param tokenId The ID of the brain token
    /// @param proposalId The ID of the proposal
    /// @param amount The amount of tokens to vote with
    function voteOnProposal(uint256 tokenId, uint256 proposalId, uint256 amount) external nonReentrant {
        if (block.timestamp >= proposalEndTime[tokenId][proposalId]) revert VotingPeriodEnded();
        
        address erc20Address = brainToERC20[tokenId];
        if (erc20Address == address(0)) revert BrainTokenNotActivated(tokenId);
        if (_blockedTokenIds[tokenId]) revert MetadataUpdateDisabled(tokenId);
        MetadataProposal storage proposal = metadataProposals[tokenId][proposalId];
        if (proposal.executed) revert ProposalAlreadyExecuted();
        
        IERC20 brainToken = IERC20(erc20Address);
        if (brainToken.balanceOf(msg.sender) < amount) revert InsufficientBrainTokens(brainToken.balanceOf(msg.sender), amount);
        
        if (!brainToken.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        
        proposal.votesLocked += amount;
        proposal.voterLocks[msg.sender] += amount;
        
        emit VoteCast(tokenId, proposalId, msg.sender, amount);
        
        if (proposal.votesLocked >= PROPOSAL_THRESHOLD) {
            _executeProposal(tokenId, proposalId);
        }
    }

    /// @notice Allows a user to withdraw their votes from a proposal
    /// @param tokenId The ID of the brain token
    /// @param proposalId The ID of the proposal
    function withdrawVotes(uint256 tokenId, uint256 proposalId) external nonReentrant {
        MetadataProposal storage proposal = metadataProposals[tokenId][proposalId];
        if (proposal.votesLocked == 0) revert ProposalDoesNotExist();
        
        uint256 amount = proposal.voterLocks[msg.sender];
        if (amount == 0) revert NoVotesToWithdraw();
        
        proposal.voterLocks[msg.sender] = 0;
        proposal.votesLocked -= amount;

        address erc20Address = brainToERC20[tokenId];
        if (!IERC20(erc20Address).transfer(msg.sender, amount)) revert TransferFailed();
    }

    /// @notice Updates the metadata for a brain token
    /// @param tokenId The ID of the brain token
    /// @param name The new name
    /// @param metadataUrl The new metadata URL
    /// @param imageUrl The new image URL
    function updateBrainMetadata(uint256 tokenId, string memory name, string memory metadataUrl, string memory imageUrl) external onlyBrainContract {
        if (_blockedTokenIds[tokenId]) revert MetadataUpdateDisabled(tokenId);
        brainMetadata[tokenId] = BrainMetadata(name, metadataUrl, imageUrl);
        emit BrainMetadataUpdated(tokenId, name, metadataUrl, imageUrl);
    }

    /// @notice Executes a proposal if it meets the required threshold
    /// @param tokenId The ID of the brain token
    /// @param proposalId The ID of the proposal
    function executeProposal(uint256 tokenId, uint256 proposalId) external onlyBrainContract {
        _executeProposal(tokenId, proposalId);
    }

    /// @notice Internal function to execute a proposal
    /// @param tokenId The ID of the brain token
    /// @param proposalId The ID of the proposal
    function _executeProposal(uint256 tokenId, uint256 proposalId) internal {
        if (_blockedTokenIds[tokenId]) revert MetadataUpdateDisabled(tokenId);
        MetadataProposal storage proposal = metadataProposals[tokenId][proposalId];
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (proposal.votesLocked < PROPOSAL_THRESHOLD) revert VotingThresholdNotMet(proposal.votesLocked, PROPOSAL_THRESHOLD);
        
        brainMetadata[tokenId] = BrainMetadata(proposal.name, proposal.metadataUrl, proposal.imageUrl);
        proposal.executed = true;
        
        emit BrainMetadataUpdated(tokenId, proposal.name, proposal.metadataUrl, proposal.imageUrl);
    }

    /// @notice Toggles the block status of a brain token's URI
    /// @param tokenId The ID of the brain token
    function toggleBlockBrainUri(uint256 tokenId) external onlyBrainContract {
        _blockedTokenIds[tokenId] = !_blockedTokenIds[tokenId];
    }

    /// @notice Gets the list of active proposals for a brain token
    /// @param tokenId The ID of the brain token
    /// @return An array of active proposal IDs
    function getActiveProposals(uint256 tokenId) external view returns (
        uint256[] memory proposalIds
    ) {
         uint256[] memory activeProposals = new uint256[](proposalCounter[tokenId]);
         uint256 count = 0;
         for (uint256 i = 0; i < proposalCounter[tokenId]; i++) {
             if (!metadataProposals[tokenId][i].executed) {
                 activeProposals[count] = i;
                 count++;
             }
         }

         assembly {
             mstore(activeProposals, count) 
        }
         return activeProposals;
     }

    /// @notice Gets the metadata for a brain token
    /// @param tokenId The ID of the brain token
    /// @return The metadata of the brain token
    function getTokenMetadata(uint256 tokenId) external view returns (
        BrainMetadata memory metadata
    ) {
        return brainMetadata[tokenId];
    }

    /// @notice Gets the ERC20 token address associated with a brain token
    /// @param tokenId The ID of the brain token
    /// @return The address of the associated ERC20 token
    function getBrainToERC20(uint256 tokenId) external view returns (address) {
        return brainToERC20[tokenId];
    }

    /// @notice Sets the ERC20 token address for a brain token
    /// @param tokenId The ID of the brain token
    /// @param erc20Address The address of the ERC20 token
    function setBrainToERC20(uint256 tokenId, address erc20Address) external onlyBrainContract {
        if (erc20Address == address(0)) revert InvalidERC20Address();
        if (brainToERC20[tokenId] != address(0)) revert BrainAlreadyActivated(tokenId);
        
        brainToERC20[tokenId] = erc20Address;
        isBrainActivated[tokenId] = true;
        
        emit BrainActivated(tokenId, erc20Address);
    }

    /// @notice Cancels a proposal
    /// @param tokenId The ID of the brain token
    /// @param proposalId The ID of the proposal
    function cancelProposal(uint256 tokenId, uint256 proposalId) external {
        if (proposalCreators[tokenId][proposalId] != msg.sender) revert NotProposalCreator();
        MetadataProposal storage proposal = metadataProposals[tokenId][proposalId];
        if (proposal.executed) revert ProposalAlreadyExecuted();
        
        delete metadataProposals[tokenId][proposalId];
        emit ProposalCancelled(tokenId, proposalId);
    }

    /// @notice Sets the voting period for a brain token
    /// @param tokenId The ID of the brain token
    /// @param period The new voting period duration
    function setVotingPeriod(uint256 tokenId, uint256 period) external onlyOwner() {
        if (period < MIN_VOTING_PERIOD || period > MAX_VOTING_PERIOD) revert InvalidVotingPeriod();
        tokenVotingPeriod[tokenId] = period;
        emit VotingPeriodSet(tokenId, period);
    }

    /// @notice Sets the address of the brain contract
    /// @param _brainContract The new address of the brain contract
    function setBrainContract(address _brainContract) external onlyOwner() {
        if (_brainContract == address(0)) revert InvalidBrainContractAddress();
        brainContract = _brainContract;
    }

    /// @notice Checks if a token's URI is blocked
    /// @param tokenId The ID of the brain token
    /// @return A boolean indicating whether the token's URI is blocked
    function isTokenURIBlocked(uint256 tokenId) external view returns (bool) {
        return _blockedTokenIds[tokenId];
    }

    event MetadataChangeProposed(uint256 indexed tokenId, uint256 proposalId, string name, string metadataUrl, string imageUrl);
    event VoteCast(uint256 indexed tokenId, uint256 proposalId, address indexed voter, uint256 amount);
    event BrainMetadataUpdated(uint256 indexed tokenId, string name, string metadataUrl, string imageUrl);
    event ProposalCreated(uint256 indexed tokenId, uint256 indexed proposalId, address creator);
    event ProposalExecuted(uint256 indexed tokenId, uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed tokenId, uint256 proposalId);
    event VotingPeriodSet(uint256 indexed tokenId, uint256 period);
    event BrainContractUpdated(address indexed newBrainContract);
    event BrainActivated(uint256 indexed tokenId, address indexed erc20Address);
}
