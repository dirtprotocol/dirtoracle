# DIRT Oracle for Data feeds

DIRT is an oracle protocol for on-chain data feeds on Ethereum. This guide walks through setting up your contracts to use the DIRT oracle for your contracts.

## Reading from the Oracle on Ropsten

The DIRT oracle maintain four price feeds: ETH/USD, PAX/USD, USDC/USD, TUSD/USD. The oracle fetches data from Coinbase, Kraken and OpenMarketCap, reports the data onchain, and writes the median value on-chain. 

The Ropsten contract address is `0x4635b0Db6Bb8F332E2eD0ff4Bf5cEB52A8409fC0` ([etherscan](https://ropsten.etherscan.io/address/0xa85f06ed8834914f3dd1473ef4337e8799efe034)). 

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

Use  `getValue` to read the value. The following examples show how to fetch data from the "DIRT ETH-USD" marketFeed. See below for the list of marketFeeds maintained by DIRT:

```solidity
contract Oracle {
  function getValue(bytes32 marketFeed) returns (int128 value) {}
}

contract OracleReader {
  function getDataFromOracle() {
    Oracle oracle = Oracle("0x4635b0Db6Bb8F332E2eD0ff4Bf5cEB52A8409fC0") 
    oracle.getValue("DIRT ETH-USD")
  }
}
```

Use `getValueAndTime` to read the value, blockTime (time written on-chain), and epochTime (time provided by the source of the price) of the update. The DIRT Oracle can support any data stream. The ETH-USD marketFeed maintained on Ropsten is referred to as `DIRT ETH-USD`. 

```solidity
contract Oracle {
  function getValueAndTime(bytes32 marketFeed) returns (int128 value, uint256 blockTime, uint256 epochTime) {}
}

contract OracleReader {
  function getDataFromOracle() {
    Oracle oracle = Oracle("0x4635b0Db6Bb8F332E2eD0ff4Bf5cEB52A8409fC0") 
    var (medianPrice, blockTime, epochTime) = oracle.getValueAndTime("DIRT ETH-USD")
  }
}
```

## Datafeeds maintained on Ropsten
Use the MarketFeed ID to reference each oracle.

| MarketFeed ID | Sources | Update Frequency | 
| --------------| ------- | ---------------- |
| DIRT ETH-USD | [OpenMarketCap](https://openmarketcap.com/cryptocurrency/pax-usd), [Coinbase](https://www.coinbase.com/price/ethereum), [Kraken](https://trade.kraken.com/markets/kraken/eth/usd) | every minute |
| PAX-USD  | [OpenMarketCap](https://openmarketcap.com/cryptocurrency/pax-usd) | every 5 minutes |
| TUSD-USD | [OpenMarketCap](https://openmarketcap.com/cryptocurrency/tusd-usd) | every 5 minutes |
| USDC-USD | [OpenMarketCap](https://openmarketcap.com/cryptocurrency/usdc-usd) | every 5 minutes |

## How price is computed

The DIRT oracle depends on public key encryption to report data onchain and verify correctness. Each price feed is created with a whitelisted set of sources. The public key of these sources are stored onchain and used to verify that only approved sources can contribute.  

To write data to a price feed, reporters fetch data from sources and write the data onchain. Reporters send a sorted list of prices onchain. The DIRT oracle contract checks that the list is sorted and each data point came from a whitelisted source. If all conditions pass, the median value is written onchain. Otherwise, the entire list is rejected.

With public key encryption, reporters cannot manipulate the price. Rather than depending on multiple reporting nodes, the DIRT oracle can update with greater frequency.

## Example: ETH-USD prices

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
  
* Can I create a datafeed for that uses custom sources? 
 
  Yes - you can call the smart contract directly to create your own datafeeds with your own sources. We include instructions on getting setup for developing on the marketfeed here: https://github.com/dirtprotocol/dirtoracle/blob/master/README-dev.md. More details to close. 

* How is this different from Chainlink?
  
  Chainlink is an on-demand oracle service. dApps call the Chainlink contract to request data from an off-chain API, and the data is fetched at the time of request. DIRT Oracle is optimized for price feeds and runs off-chain reporters to continuously push data on-chain. The choice between Chainlink and DIRT is a choice between update frequency and flexibility. If you need flexibility in the URLs hit, Chainlink is a good option. If you need a regularly repeating price feed that can be fetched instantly, DIRT is a good fit.

* How is this different from Augur?
  
  This is not a prediction market. The DIRT oracle is focused on data that's regularly updating like price feeds.
  
* Why is this better than forking the code and building my own oracle?

  DIRT maintains the insfrastucture to keep the oracle running by keeping the reporters running. We are also partnering with exchanges to sign messages so the data is trusted. 

* How can I see the latest prices reported onchain? 
  
  We are launching a dashboard that gives users a historical view of marketfeeds shortly. 

* How can I reach you? 

  If you have a feature request, please submit an issue. We welcome PR contributions! For all other inquires, send an email to yin [at] dirtprotocol.com
