// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title BrainERC20 Contract
/// @notice This contract implements the Brain ERC20 with burnable and permit functionalities
/// @dev Inherits from ERC20, ERC20Burnable, ERC20Permit, and Ownable
contract BrainERC20 is ERC20, ERC20Burnable, ERC20Permit, Ownable {
    /// @notice Error thrown when trying to initialize an already initialized contract
    error AlreadyInitialized();
    /// @notice Error thrown when trying to perform actions on an uninitialized contract
    error NotInitialized();
    /// @notice Error thrown when an unauthorized address tries to call a restricted function
    error UnauthorizedAccess();
    error InvalidInput();
    error InsufficientContributorShare();
    error AlreadyHasContributors();

    /// @notice Flag to track whether the contract has been initialized
    bool private _initialized;

    /// @notice Address of the brain contract
    address public brainContract;
    mapping(address => uint256) public contributorShares;
    uint256 public totalContributorShares;

    /// @notice Modifier to restrict access to only the brain contract
    modifier onlyBrainContract() {
        if (msg.sender != brainContract) revert UnauthorizedAccess();
        _;
    }

    /// @notice Constructor for the BrainERC20 contract
    /// @dev Initializes the contract with empty name and symbol, and no owner
    constructor() ERC20("", "") ERC20Permit("") Ownable(address(0)) {
        _initialized = false;
    }

    /// @notice Initializes the BrainERC20 token
    /// @dev Can only be called once and only by the brain contract
    /// @param name_ The name of the token
    /// @param symbol_ The symbol of the token
    /// @param initialSupply The initial supply of tokens to mint
    /// @param tokenOwner The address that will own the minted tokens and the contract
    /// @param _brainContract The address of the brain contract
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address tokenOwner,
        address _brainContract
    ) external {
        if (msg.sender != _brainContract) revert UnauthorizedAccess();
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;
        _setName(name_);
        _setSymbol(symbol_);
        _mint(tokenOwner, initialSupply);
        _transferOwnership(tokenOwner);
        brainContract = _brainContract;
    }

    /// @notice Mints new tokens
    /// @dev Can only be called by the contract owner
    /// @param to The address that will receive the minted tokens
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) public onlyOwner {
        if (!_initialized) revert NotInitialized();
        _mint(to, amount);
    }

    /// @notice Internal function to set the token name
    /// @dev Uses assembly to directly set the storage slot
    /// @param name_ The new name of the token
    function _setName(string memory name_) internal {
        assembly {
            sstore(0x30, name_)
        }
    }

    /// @notice Internal function to set the token symbol
    /// @dev Uses assembly to directly set the storage slot
    /// @param symbol_ The new symbol of the token
    function _setSymbol(string memory symbol_) internal {
        assembly {
            sstore(0x31, symbol_)
        }
    }

    /// @notice Transfers tokens to a specified address
    /// @dev Overrides the ERC20 transfer function to check for initialization
    /// @param to The address to transfer to
    /// @param amount The amount of tokens to transfer
    /// @return A boolean indicating whether the transfer was successful
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (!_initialized) revert NotInitialized();
        return super.transfer(to, amount);
    }

    /// @notice Transfers tokens from one address to another
    /// @dev Overrides the ERC20 transferFrom function to check for initialization
    /// @param from The address to transfer from
    /// @param to The address to transfer to
    /// @param amount The amount of tokens to transfer
    /// @return A boolean indicating whether the transfer was successful
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        if (!_initialized) revert NotInitialized();
        return super.transferFrom(from, to, amount);
    }


    function setContributorShares(address[] calldata contributors, uint256[] calldata shares) external onlyBrainContract {
        if (!_initialized) revert NotInitialized();
        if (contributors.length != shares.length) revert InvalidInput();
        if (totalContributorShares > 0) revert AlreadyHasContributors();
        
        uint256 totalShares = 0;
        for (uint256 i = 0; i < contributors.length; i++) {
            if (contributors[i] == address(0)) revert InvalidInput();
            if (shares[i] == 0) revert InvalidInput();
            
            contributorShares[contributors[i]] = shares[i];
            totalShares += shares[i];
            emit ContributorSharesUpdated(contributors[i], shares[i]);
        }
        
        if (totalShares != 1e18) revert InvalidSharesTotal();
        totalContributorShares = totalShares;
    }


    function updateContributorShares(address contributor, uint256 newShare) external onlyBrainContract {
        if (!_initialized) revert NotInitialized();
        
        totalContributorShares -= contributorShares[contributor];
        contributorShares[contributor] = newShare;
        totalContributorShares += newShare;
        
        emit ContributorSharesUpdated(contributor, newShare);
    }

    
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (from != address(0) && to != address(0)) {
            uint256 fromShare = contributorShares[from];
            if (fromShare > 0) {
                uint256 currentBalance = balanceOf(from);
                uint256 minRequired = (fromShare * totalSupply()) / 1e18;
                if (currentBalance - amount < minRequired) revert InsufficientContributorShare();
            }
        }
        
        super._update(from, to, amount);
    }

    event ContributorSharesUpdated(address indexed contributor, uint256 shares);
}
