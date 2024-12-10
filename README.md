# Brains-Core

Concept for the Brains system ++ = ERC721, metadata management, ERC20 clones representing fractonal ownership for $BCRED contributors.

## Contracts

- `BrainsERC721.sol`: The main ERC721 contract for Brains NFTs.
- `BrainMetadata.sol`: Manages metadata for Brains NFTs, including proposals and voting mechanisms.
- `BrainERC20.sol`: ERC20 linked with each Brain tokenId.

## Development

This project uses [Foundry](https://book.getfoundry.sh/) for development and testing.

To get started:

1. Clone the repository
2. Install dependencies: `forge install`
3. Compile contracts: `forge build`
4. Run tests: `forge test`

## License

[MIT License](LICENSE)


## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
