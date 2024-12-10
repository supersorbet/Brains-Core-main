// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/forge-std/src/Test.sol";
import "../src/BrainMetadata.sol";
import "../src/BrainsERC721.sol";
import "../src/BrainERC20.sol";

contract BrainMetadataTest is Test {
    BrainMetadata public metadata;
    Brains public brains;
    BrainERC20 public brainERC20Implementation;

    function setUp() public {
        brainERC20Implementation = new BrainERC20();
        metadata = new BrainMetadata();
        brains = new Brains(address(brainERC20Implementation), address(metadata));
        metadata.setBrainsContract(address(brains));
    }

    function testProposeMetadataChange() public {
        uint256 tokenId = brains.mint();
        string memory name = "New Name";
        string memory metadataUrl = "https://example.com/metadata";
        string memory imageUrl = "https://example.com/image.png";
        
        metadata.proposeMetadataChange(tokenId, name, metadataUrl, imageUrl);
        
        (string memory proposedName, string memory proposedMetadataUrl, string memory proposedImageUrl, , , ) = metadata.metadataProposals(tokenId, 0);
        assertEq(proposedName, name);
        assertEq(proposedMetadataUrl, metadataUrl);
        assertEq(proposedImageUrl, imageUrl);
    }
}