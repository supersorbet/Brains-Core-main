// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCastLib} from "solady/src/utils/SafeCastLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {UUPSUpgradeable} from "solady/src/utils/UUPSUpgradeable.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";

contract BrainDataLib is UUPSUpgradeable, OwnableRoles {
    using SafeCastLib for uint256;
    using FixedPointMathLib for uint256;

    /// @dev `keccak256(bytes("RolesUpdated(address,uint256)"))`.
    uint256 private constant _ROLES_UPDATED_EVENT_SIGNATURE =
        0x715ad5ce61fc9595c7b415289d59cf203f23a94fa06f04af7e489a0a76e1fe26;

    /// @dev The role slot of `user` is given by:
    /// ```
    ///     mstore(0x00, or(shl(96, user), _ROLE_SLOT_SEED))
    ///     let roleSlot := keccak256(0x00, 0x20)
    uint256 private constant _ROLE_SLOT_SEED = 0x8b78c6d8;

    // @constant @OWNER_ROLE @Roles for different permissions within the contract.
    uint256 public constant OWNER_ROLE = _ROLE_0;

    struct BrainERC20Info {
        uint256 brainId;
        address erc20Address;
        uint256 totalSupply;
        uint256 userBalance;
        uint256 userOwnershipPercentage;
        uint256 contributorShare;
        bool isActivated;
    }

    struct ContributionInfo {
        uint256 brainId;
        uint256 contribution;
        uint256 ownershipPercentage;
        uint256 votingPower;
        uint256[] activeProposals;
    }

    struct CollectiveMintInfo {
        uint256 brainId;
        uint256 totalContributions;
        uint256 contributorCount;
        address[] topContributors;
        uint256[] topContributions;
        uint256 percentageComplete;
        bool readyToMint;
    }

    struct MetadataInfo {
        string name;
        string metadataUrl;
        string imageUrl;
        uint256 activeProposalCount;
        bool isURIBlocked;
    }

    constructor() {
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, OWNER_ROLE);
    }

    function initialize(address initialOwner) external {
        if (owner() != address(0)) revert("Already initialized");
        _initializeOwner(initialOwner);
        _grantRoles(initialOwner, OWNER_ROLE);
    }

    function getUserCompleteData(address brainsContract, address user)
        external
        view
        returns (
            BrainERC20Info[] memory ownedBrains,
            ContributionInfo[] memory contributedBrains,
            uint256 totalStakedAmount,
            uint256 totalVotingPower
        )
    {
        Brains brains = Brains(brainsContract);
        uint256 balance = brains.balanceOf(user);
        
        ownedBrains = new BrainERC20Info[](balance);
        uint256 totalVP = 0;
        
        for (uint256 i = 0; i < balance; i++) {
            uint256 brainId = brains.tokenOfOwnerByIndex(user, i);
            ownedBrains[i] = _getBrainERC20Info(brains, brainId, user);
            totalVP += ownedBrains[i].userBalance;
        }

        (uint256[] memory brainIds, uint256[] memory contributions,) = brains.getUserContributedBrains(user);
        contributedBrains = new ContributionInfo[](brainIds.length);
        
        for (uint256 i = 0; i < brainIds.length; i++) {
            contributedBrains[i] = _getContributionInfo(brains, brainIds[i], user);
        }

        totalStakedAmount = brains.getStakedAmount(user);
        totalVotingPower = totalVP;
    }

    function getCollectiveMintDetails(address brainsContract, uint256[] calldata brainIds)
        external
        view
        returns (CollectiveMintInfo[] memory mintInfo)
    {
        mintInfo = new CollectiveMintInfo[](brainIds.length);
        Brains brains = Brains(brainsContract);
        
        for (uint256 i = 0; i < brainIds.length; i++) {
            (
                uint256 totalContributions,
                uint256 contributorCount,
                address[] memory topContributors,
                uint256[] memory topContributions
            ) = brains.getCollectiveMintProgress(brainIds[i]);

            mintInfo[i] = CollectiveMintInfo({
                brainId: brainIds[i],
                totalContributions: totalContributions,
                contributorCount: contributorCount,
                topContributors: topContributors,
                topContributions: topContributions,
                percentageComplete: (totalContributions * 1e18) / brains.TOKENS_PER_NFT(),
                readyToMint: totalContributions >= brains.TOKENS_PER_NFT()
            });
        }
    }

    function getBrainMetadataDetails(address brainsContract, uint256[] calldata brainIds)
        external
        view
        returns (MetadataInfo[] memory metadataInfo)
    {
        metadataInfo = new MetadataInfo[](brainIds.length);
        Brains brains = Brains(brainsContract);
        
        for (uint256 i = 0; i < brainIds.length; i++) {
            IBrainMetadata metadata = IBrainMetadata(brains.metadataContract());
            BrainMetadata.BrainMetadata memory brainMeta = metadata.getTokenMetadata(brainIds[i]);
            uint256[] memory activeProposals = metadata.getActiveProposals(brainIds[i]);
            
            metadataInfo[i] = MetadataInfo({
                name: brainMeta.name,
                metadataUrl: brainMeta.metadataUrl,
                imageUrl: brainMeta.imageUrl,
                activeProposalCount: activeProposals.length,
                isURIBlocked: metadata.isTokenURIBlocked(brainIds[i])
            });
        }
    }

    function _getBrainERC20Info(Brains brains, uint256 brainId, address user) internal view returns (BrainERC20Info memory) {
        address erc20Address = brains.getBrainERC20(brainId);
        BrainERC20Info memory info;
        info.brainId = brainId;
        info.erc20Address = erc20Address;

        if (erc20Address != address(0)) {
            IERC20 brainToken = IERC20(erc20Address);
            info.totalSupply = brainToken.totalSupply();
            info.userBalance = brainToken.balanceOf(user);
            info.userOwnershipPercentage = info.totalSupply > 0 
                ? info.userBalance.mulDivDown(1e18, info.totalSupply)
                : 0;
        }

        return info;
    }

    function _getContributionInfo(Brains brains, uint256 brainId, address user) internal view returns (ContributionInfo memory) {
        ContributionInfo memory info;
        info.brainId = brainId;
        info.contribution = brains.getContribution(brainId, user);
        uint256 totalContributions = brains.getBrainTotalContributions(brainId);
        info.ownershipPercentage = totalContributions > 0 
            ? info.contribution.mulDivDown(1e18, totalContributions)
            : 0;
        return info;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRoles(OWNER_ROLE) {}

    function encodeMulticallData(address brainsContract, address user) public pure returns (bytes[] memory) {
        bytes[] memory calls = new bytes[](4);
        
        calls[0] = abi.encodeWithSelector(
            this.getUserCompleteData.selector,
            brainsContract,
            user
        );
        
        calls[1] = abi.encodeWithSelector(
            this.getCollectiveMintDetails.selector,
            brainsContract,
            user
        );
        
        calls[2] = abi.encodeWithSelector(
            this.getBrainMetadataDetails.selector,
            brainsContract,
            user
        );
        
        return calls;
    }

    function decodeMulticallResults(bytes[] memory results) public pure returns (
        BrainERC20Info[] memory ownedBrains,
        ContributionInfo[] memory contributedBrains,
        CollectiveMintInfo[] memory mintInfo,
        MetadataInfo[] memory metadataInfo
    ) {
        (ownedBrains, contributedBrains,,) = abi.decode(results[0], (BrainERC20Info[], ContributionInfo[], uint256, uint256));
        mintInfo = abi.decode(results[1], (CollectiveMintInfo[]));
        metadataInfo = abi.decode(results[2], (MetadataInfo[]));
    }

    function getBatchedBrainData(address brainsContract, address user) external view returns (
        BrainERC20Info[] memory ownedBrains,
        ContributionInfo[] memory contributedBrains,
        CollectiveMintInfo[] memory mintInfo,
        MetadataInfo[] memory metadataInfo
    ) {
        bytes[] memory calls = encodeMulticallData(brainsContract, user);
        bytes[] memory results = Brains(brainsContract).multicall(calls);
        return decodeMulticallResults(results);
    }
}

interface Brains {
    function balanceOf(address owner) external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function getBrainERC20(uint256 tokenId) external view returns (address);
    function getStakedAmount(address staker) external view returns (uint256);
    function getContribution(uint256 brainId, address contributor) external view returns (uint256);
    function getBrainTotalContributions(uint256 brainId) external view returns (uint256);
    function getUserContributedBrains(address user) external view returns (uint256[] memory);
    function getBrainContributors(uint256 brainId) external view returns (address[] memory);
    function TOKENS_PER_NFT() external view returns (uint256);
    function metadataContract() external view returns (address);
}

interface IBrainMetadata {
    function getTokenMetadata(uint256 tokenId) external view returns (BrainMetadata.BrainMetadata memory);
    function getActiveProposals(uint256 tokenId) external view returns (uint256[] memory);
    function isTokenURIBlocked(uint256 tokenId) external view returns (bool);
}

library BrainMetadata {
    struct BrainMetadata {
        string name;
        string metadataUrl;
        string imageUrl;
    }
}