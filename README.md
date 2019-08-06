# DIRT Oracle for Pricefeeds

DIRT is an protocol for onchain pricefeeds. This readme walks through how you can use the DIRT pricefeed to get the latest ETH/USD on Ropsten. 

## Reading from the oracle on Ropsten
The DIRT oracle is deployed on Ropsten and we maintain an ETH-USD price feed. The oracle fetches data from Coinbase, Kraken and OpenMarketCap, and stores the median value onchain. The price updates every minute and you can view the historical data on our dashboard:  

The oracle is deployed on Ropsten at the address [`0xa85F06Ed8834914F3Dd1473EF4337e8799eFe034`](https://ropsten.etherscan.io/address/0xa85f06ed8834914f3dd1473ef4337e8799efe034).  

There are two methods you can use to fetch data from the oracle: 
```
function getValue(bytes32 marketFeed) external view readersOnly(marketFeed) returns (int128) {
  return marketFeeds_data[marketFeed].value;
}

function getValueAndTime(bytes32 marketFeed) external view readersOnly(marketFeed) returns (int128 value, uint256 blockTime, uint256 epochTime) {
  MarketFeedData storage m = marketFeeds_data[marketFeed];
  return (m.value, m.blockTime, m.epochTime);
}
```

To get the latest median price, blockTime (time written onchain), and epochTime (time from the written source) of the update. 

```
Oracle oracle = Oracle("0xa85F06Ed8834914F3Dd1473EF4337e8799eFe034")
var (medianPrice, blockTime, epochTime) = oracle.getValueAndTime("DIRT ETH/USD")
```

To get the latest median price:
```
Oracle oracle = Oracle("0xa85F06Ed8834914F3Dd1473EF4337e8799eFe034")
var medianPrice = oracle.getValue("DIRT ETH/USD")
```

## Example

The following prices are reported from Coinbase, Kraken, and OpenMarketCap during a round: 
```
[
  {
    source: Kraken,
    price: $210, 
    epochtime: 1565132869
  },
  {
    source: Coinbase,
    price: $205, 
    epochtime: 1565132888
  },
  {
    source: OpenMarketCap,
    price: $212, 
    epochtime: 1565132969
  },
]
```
Each source signs the prices to allow the onchain smart contract to verify that only data from approved sources can contribute to the price feed. In the above example, Kraken is the median value and the price is written onchain. The `epochTime` is the time in seconds at which the exchange reported the price (epochTime is reported by the source API). The `blockTime` is the time in seconds at which the block with the updated median price is mined (blocktime is reported by the miner). 

## Local setup 
You can deploy the contracts on Ganache and use it locally for testing by following the instructions below. 

### Truffle Dev

Install version 5.0.14. The latest version of 5.0.15 has a non-working debugger at the time of writing this read me. 

```
yarn global add truffle@5.0.14
yarn install
```

### Running

Download and run Ganache: [Ganache](https://truffleframework.com/ganache)

Compile the contracts

```
truffle compile
```

Deploy the contracts onto Ganache

```
truffle migrate --reset
```

Interact with the contract using the truffle console

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

```
truffle debug 0x[the transaction hash]
```

## FAQ
* Do you support other price feeds? Currently, we maintain the ETH/USD feed and have plans to add additional price feeds. Submit an issue with pricefeed requestse.
* How is this different from Chainlink? Chainlink is an on-demand oracle service. dApps call the Chainlink contract to request data from an off-chain API, and the data is fetched at the time of request. DIRT is optimized for pricefeeds and run offchain reporters to continuously push data on-chain. The choice between Chainlink and DIRT is a choice between update frequency and flexibility. If you need flexibility in the URLs hit, Chainlink is a good option. If you need a regularly repeating price feed, DIRT is a good fit.
* How is this different from Augur? This is not a prediction market. The DIRT oracle is focused on data that's regularly repeating like pricefeeds. 

