# Contract developer instructions

## Run DIRT Oracle locally

You can deploy the contracts on Ganache and use it locally for testing by following the instructions below.

1. Install Truffle version 5.0.14. The latest version of 5.0.15 has a non-working debugger at the time of writing this README.

    ```shell
    yarn global add truffle@5.0.14
    yarn install
    ```

2. Download and run [Ganache](https://truffleframework.com/ganache).

3. Compile the contracts.

    ```shell
    truffle compile
    ```

4. Deploy the contracts onto Ganache.

    ```shell
    truffle migrate --reset
    ```

5. Interact with the contract using the truffle console.

    ```shell
    truffle console
    > let leverest = await Leverest.deployed()
    > let accounts = await web3.eth.getAccounts()
    > tx = await leverest.lend({ from: accounts[1], value: web3.utils.toWei("2") })
    ```

### Optional

Run tests:

```shell
truffle test
```

Debug transactions:

```shell
truffle debug 0x[the transaction hash]
```
