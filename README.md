# DIRT Oracle

## Truffle Dev

### Setup

Those buttheads at truffle delivered a non-working debugger with their latest 5.0.15. So install 5.0.14.

```
yarn global add truffle@5.0.14
yarn install
```

### Running

Make sure you have a copy of [Ganache](https://truffleframework.com/ganache) running first.

To compile the contracts

```
truffle compile
```

Then deploy/migrate the contracts onto Ganache

```
truffle migrate --reset
```

Then you can exercise it using the truffle console

```
truffle console
> let leverest = await Leverest.deployed()
> let accounts = await web3.eth.getAccounts()
> tx = await leverest.lend({ from: accounts[1], value: web3.utils.toWei("2") })
```

### Running Tests

```
truffle test
```

### Debugging

you just run

```
truffle debug 0x[the transaction hash]
```
