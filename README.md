# DIRT Oracle for Data feeds

DIRT is an oracle protocol for on-chain data feeds on Ethereum. This guide walks through setting up your contracts to use the DIRT oracle to read the current ETH/USD value on Ropsten.

## Reading from the Oracle on Ropsten

The DIRT oracle maintain an ETH/USD price feed. The oracle fetches data from Coinbase, Kraken and OpenMarketCap, and stores the median value of these on-chain. The value updates every minute and you can view the historical data on the DIRT dashboard: TODO 

The Ropsten contract address is `0xa85F06Ed8834914F3Dd1473EF4337e8799eFe034` ([etherscan](https://ropsten.etherscan.io/address/0xa85f06ed8834914f3dd1473ef4337e8799efe034)). 

Contracts have two options for reading latest data from a DIRT oracle feed:

```solidity
function getValue(bytes32 marketFeed) external view readersOnly(marketFeed) returns (int128) {
  return marketFeeds_data[marketFeed].value;
}

function getValueAndTime(bytes32 marketFeed) external view readersOnly(marketFeed) returns (int128 value, uint256 blockTime, uint256 epochTime) {
  MarketFeedData storage m = marketFeeds_data[marketFeed];
  return (m.value, m.blockTime, m.epochTime);
}
```

Use  `getValue` to read the value:

```solidity
Oracle oracle = Oracle("0xa85F06Ed8834914F3Dd1473EF4337e8799eFe034")
var medianPrice = oracle.getValue("DIRT ETH/USD")
```

Use `getValueAndTime` to read the value, blockTime (time written on-chain), and epochTime (time provided by the source of the price) of the update.

```solidity
Oracle oracle = Oracle("0xa85F06Ed8834914F3Dd1473EF4337e8799eFe034")
var (medianPrice, blockTime, epochTime) = oracle.getValueAndTime("DIRT ETH/USD")
```

## How price is computed

The following prices are reported from Coinbase, Kraken, and OpenMarketCap during a round:

```
[
  {
    source: Kraken,
    price: $210.340352,
    epochtime: 1565132869
  },
  {
    source: Coinbase,
    price: $205.230209421,
    epochtime: 1565132888
  },
  {
    source: OpenMarketCap,
    price: $212.2599985,
    epochtime: 1565132969
  },
]
```

Each source signs the price data it publishes, allowing the smart contract to verify and enforce that only data from approved sources can contribute to the price feed. In the above example, $210.340352 from Kraken is the median value and the price is written on-chain. The `epochTime` is the time in seconds at which the exchange reported the price (epochTime is reported by the source API). The `blockTime` is the time in seconds at which the block with the updated median price is mined (blocktime is reported by the miner).

## FAQ

* Do you support other price feeds?
  
  Currently, DIRT maintains the ETH/USD feed and has plans to add additional price feeds. To request a specific feed, submit an issue.

* How is this different from Chainlink?
  
  Chainlink is an on-demand oracle service. dApps call the Chainlink contract to request data from an off-chain API, and the data is fetched at the time of request. DIRT Oracle is optimized for price feeds and runs off-chain reporters to continuously push data on-chain. The choice between Chainlink and DIRT is a choice between update frequency and flexibility. If you need flexibility in the URLs hit, Chainlink is a good option. If you need a regularly repeating price feed that can be fetched instantly, DIRT is a good fit.

* How is this different from Augur?
  
  This is not a prediction market. The DIRT oracle is focused on data that's regularly updating like price feeds.
