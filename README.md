# DIRT Oracle for Data feeds

DIRT is an oracle protocol that is designed for regularly updating data streams (i.e. pricefeeds). Our protocol design uses  public key encryption to submit provably correct data on-chain. A decentralized network of reporters transmit data from offchain sources (ex: Coinbase API) to the onchain Oracle smart contract. With public key encryption, the smart contract verifies that only approved sources can submit data onchain to prevent reporters from manipulating data in-transit.  

The DIRT oracle is **live on the Ropsten testnet**. This guide walks through how to connect your smart contracts to the oracles to read from up-to-date datafeeds.

## Current feature list

* Support for four onchain datafeeds with `ETH/USD`, `PAX/USD`, `USDC/USD`, `TUSD/USD` - even more upcoming soon
* Dashboard to track current datafeed: https://ropsten.dirtoracle.com/
* Smart contract features that allow you to create and read from new datasets  
* Out of the box service to create and maintain your own datafeed. Opensourced code to run a reporter and proxySigner (coming soon) 

## Protocol design (WIP)
To find out more details on the oracle check out the working draft of the protocol design: [Protocol Design Link](https://github.com/dirtprotocol/dirtoracle/blob/master/Protocol-Design.md). 

Welcome your feedback!


## Reading from the Oracle on Ropsten

The DIRT oracle maintains four price feeds: `ETH/USD`, `PAX/USD`, `USDC/USD`, `TUSD/USD`. The oracle fetches data from Coinbase, Kraken and OpenMarketCap, reports the data on-chain, and writes the median value on-chain. 

The Ropsten contract address is `0x19BB7bEdB7D180b25E216ff8fC3D9d3487a54239`.

Contracts have two options for reading latest data from a DIRT oracle feed:

```solidity
function getValue(bytes32 dataFeed) external view readersOnly(dataFeed) returns (int128) {
  return dataFeeds_data[dataFeed].value;
}

function getValueAndTime(bytes32 dataFeed) external view readersOnly(dataFeed) returns (int128 value, uint256 blockTime, uint256 epochTime) {
  DataFeedData storage m = dataFeeds_data[dataFeed];
  return (m.value, m.blockTime, m.epochTime);
}
```

Use  `getValue` to read the value. The following examples show how to fetch data from the "DIRT ETH-USD" dataFeed. See below for the list of dataFeeds maintained by DIRT:

```solidity
contract Oracle {

  function getValue(bytes32 dataFeed) external view returns (int128 value) {}
  
  function getValueAndTime(bytes32 dataFeed) external view returns (
    int128 value,
    uint256 blockTime,
    uint256 epochTime
  ) {}

}

contract OracleReader {

    function getDataFromOracle() public view returns (int128) {
        Oracle oracle = Oracle(0x19BB7bEdB7D180b25E216ff8fC3D9d3487a54239);
        int128 medianPrice = oracle.getValue("DIRT ETH-USD");
        return medianPrice;
    }
    
}
```

Use `getValueAndTime` to read the value, blockTime (time written on-chain), and epochTime (time provided by the source of the price) of the update. The DIRT Oracle can support any data stream. The ETH-USD dataFeed maintained on Ropsten is referred to as `DIRT ETH-USD`. 

```solidity
contract Oracle {

  function getValue(bytes32 dataFeed) external view returns (int128 value) {}
  
  function getValueAndTime(bytes32 dataFeed) external view returns (
    int128 value,
    uint256 blockTime,
    uint256 epochTime
  ) {}

}

contract OracleReader {

    function getDataFromOracle() public view returns (int128) {
        Oracle oracle = Oracle(0x19BB7bEdB7D180b25E216ff8fC3D9d3487a54239);
        int128 medianPrice = oracle.getValueAndTime("DIRT ETH-USD");
        return medianPrice;
    }
    
}
```

## Datafeeds maintained on Ropsten
Use the DataFeed ID to reference each oracle.

| DataFeed ID | Sources | Update Frequency | 
| --------------| ------- | ---------------- |
| DIRT ETH-USD | [OpenMarketCap](https://openmarketcap.com/cryptocurrency/pax-usd), [Coinbase](https://www.coinbase.com/price/ethereum), [Kraken](https://trade.kraken.com/markets/kraken/eth/usd) | every minute |
| PAX-USD  | [OpenMarketCap](https://openmarketcap.com/cryptocurrency/pax-usd) | every 5 minutes |
| TUSD-USD | [OpenMarketCap](https://openmarketcap.com/cryptocurrency/tusd-usd) | every 5 minutes |
| USDC-USD | [OpenMarketCap](https://openmarketcap.com/cryptocurrency/usdc-usd) | every 5 minutes |

## How does the oracle work?

### What is an oracle?
An oracle brings off-chain data onto the blockchain for use in smart contracts. Existing oracle designs are optimized for one-time responses and are not suited for regularly updating data streams. Previous efforts at building data feeds oracles have been centralized or expensive to maintain. DIRT is building an oracle protocol that is provably correct using public key encryption.

Any user can create a DataFeed by whitelisting a set of approved Sources. The Oracle contract maintains a whitelist of Sources and the public key(s) for each Source in the DataFeed. For example, Alice can create a DataFeed for ETH-JPY that accepts data from three Sources: Liquid, Coinbase, and Bittrex. For each DataFeed, the Oracle contract verifies onchain that the data submitted came from whitelisted Sources using the exchange’s stored public key. 

You can find more details in our protocol draft: https://github.com/dirtprotocol/dirtoracle/blob/master/Protocol-Design.md


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

## Creating a datafeed (WIP)
Creating a datafeed is more involved. To help you get started, we've opensourced utilities to sign messsage (ProxySigner) and push data onchain (Reporters).

Steps to creating a datafeed:
* Create a datafeed in the smart contract - Call the contract directly to create a new datafeed. Dashboard interface coming soon. 
* Whitelist sources to the datafeed - Add the address (i.e. public key) of whitelisted ProxySigners to the contract. Only messages signed by whitelisted sources can submit data onchain.
* Run a ProxySigner or use a DIRT run ProxySigner - ProxySigners fetch data from datasources and sign messages on their behalf. See the [ProxySigner](https://github.com/dirtprotocol/proxysigner/blob/master/README.md) docs.
* Run a Reporter - Reporters transport data from ProxySigners to the Smart Contract. See the [Reporter](https://github.com/dirtprotocol/reporter) docs.
* Check prices hit the contract - Read from the oracle and check that prices made it onchain. The new datafeed will not appear on the dashboard. 

### DIRT operated ProxySigners
DIRT operates ProxySigners / Sources for three sources. Instead of running a ProxySigner, you can create a datafeed and add the address of one of the following sources. You will still need to run a reporter to push data onchain.

| ProxySigner | URL | Address (Public Key) | Datasets |
| ----------- | ----------- |----------- |----------- |
| OpenMarketCap | https://us-central1-dirthub.cloudfunctions.net/proxysigner-kraken?pair=BTCUSD | 0xA1B3457bdBd16A5Cf1b1D460C9A53F0276959BC8 | [https://openmarketcap.com/](https://openmarketcap.com/) |
| Coinbase | https://us-central1-dirthub.cloudfunctions.net/proxysigner-coinbase?pair=BTC/USD | 0x450A47eD3dEc0Db7749A6c76425E8FD4b16cc4c2 | [Check Coinbase API for supported assets](https://developers.coinbase.com/api/v2) |
| Kraken | https://us-central1-dirthub.cloudfunctions.net/proxysigner-kraken?pair=ADA/BTC | 0x4444bA94D9eCdBFB2C94F397864E126FbAb77fBb | [Kraken Assets - use wsname](https://api.kraken.com/0/public/AssetPairs) |


## FAQ

* Do you support other price feeds?
  
  Currently, DIRT maintains the ETH/USD feed and has plans to add additional price feeds. To request a specific feed, submit an issue. 
  
* Can I create a datafeed for that uses custom sources? 
 
  Yes - you can call the smart contract directly to create your own datafeeds with your own sources. We include instructions on getting setup for developing on the datafeed here: https://github.com/dirtprotocol/dirtoracle/blob/master/README-dev.md. More details to close. 

* How is this different from Chainlink?
  
  Chainlink is an on-demand oracle service. dApps call the Chainlink contract to request data from an off-chain API, and the data is fetched at the time of request. DIRT Oracle is optimized for price feeds and runs off-chain reporters to continuously push data on-chain. The choice between Chainlink and DIRT is a choice between update frequency and flexibility. If you need flexibility in the URLs hit, Chainlink is a good option. If you need a regularly repeating price feed that can be fetched instantly, DIRT is a good fit.

* How is this different from Augur?
  
  This is not a prediction data. The DIRT oracle is focused on data that's regularly updating like price feeds.
  
* Why is this better than forking the code and building my own oracle?

  DIRT maintains the insfrastucture to keep the oracle running by keeping the reporters running. We are also partnering with exchanges to sign messages so the data is trusted. 

* How can I see the latest prices reported onchain? 
  
  We are launching a dashboard that gives users a historical view of datafeeds shortly. 
  
* What is the SLO for onchain prices?

  Prices on testnet will be maintained on a best-effort basis.

* How can I reach you? 

  If you have a feature request, please submit an issue. We welcome PR contributions! For all other inquires, send an email to yin [at] dirtprotocol.com
  
## License
MIT
