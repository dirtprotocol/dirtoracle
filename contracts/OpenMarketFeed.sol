pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2; // Needed for using bytes[] parameter type.

contract OpenMarketFeed {
  struct MarketFeedSource {
    bytes32 marketId;
  }

  // Anyone can create a new MarketFeed with `createMarketFeed()`.
  // Only the managers of a MarketFeed can edit parameters (whitelists and config) of the marketFeed.
  // Anyone can post updates to the marketFeed data with `post()`, but the data is only accepted if it meets the marketFeed's configured criteria.
  struct MarketFeedConfig {
    bytes32 marketId;
    mapping (bytes32 => bytes32) sourceToMarketId;

    // Whitelists, all editable only by managers
    mapping (bytes32 => address[]) sourceToSigners;
    mapping (address => bytes32) signerToSource;

    mapping (bytes32 => uint16) sourceToId;
    mapping (uint16 => bytes32) idToSource;
    // Source IDs are assigned in incrementing order in a packed manner in the range [1, 511].
    // If a source is deleted, the last source is reassigned its ID and the last source ID is freed up.
    uint16 lastSourceId;

    mapping (address => bool) readers;
    mapping (address => bool) managers;

    uint256 minRequiredSources;
  }

  struct MarketFeedData {
    // Last accepted data
    uint256 price;
    // uint256[] rawPrices;
    uint256 blockTime;
    uint256 epochTime;
  }

  /*************** State attributes ***************/

  // A map from marketFeed name to MarketFeed.
  mapping (bytes32 => MarketFeedConfig) public marketFeeds_config;
  mapping (bytes32 => MarketFeedData) marketFeeds_data;

  /*************** Emitted Events *****************/

  // when a market feed is created
  event MarketFeedCreation(bytes32 marketFeed, bytes32 marketId, uint256 minRequiredSources, address creator);

  // when an existing manager adds a new manager
  event ManagerAddition(
    address indexed manager,
    bytes32 indexed marketFeed,
    address indexed newManager
  );

  // when an existing manager removes a existing manager
  event ManagerRemoval(
    address indexed manager,
    bytes32 indexed marketFeed,
    address indexed firedManager
  )

  // when a source is added
  event SourceAddition(bytes32 indexed marketFeed, bytes32 source, bytes32 sourceMarketId, address indexed manager);

  // when a source is removed
  event SourceRemoval(bytes32 indexed marketFeed, bytes32 source, address indexed manager);

  // when a signer is added
  event SignerAddition(bytes32 indexed marketFeed, bytes32 source, address signer, address indexed manager);

  // when a signer is removed
  event SignerRemoval(bytes32 indexed marketFeed, bytes32 source, address signer, address manager);

  // when min required sources is updated
  event MinRequiredSourcesUpdated(bytes32 indexed marketFeed, uint256 newMin, address manager);

  // when a valid source reports a price
  event SourceReported(bytes32 marketFeed, bytes32 source, address reporter, uint256 epochTime);

  // when contract writes a median price
  event MedianPriceWritten(bytes32 marketFeed, uint256 val, uint256 age, address reporterAddress);

  /*********************** Modifiers *******************/

  modifier managersOnly(bytes32 marketFeed) {
    require(marketFeeds_config[marketFeed].managers[msg.sender], 'not a manager');
    _;
  }

  modifier readersOnly(bytes32 marketFeed) {
    require(marketFeeds_config[marketFeed].readers[msg.sender], "unauthorized reader");
    _;
  }

  /*********************** Public methods *******************/

  constructor() public {}

  /*********************** External methods *******************/

  // Posts a new sorted price list for a marketFeed.
  function post(bytes32 marketFeed, bytes32[] calldata marketIds, uint256[] calldata prices, uint256[] calldata epochTime,
      bytes[] calldata signatures) external {
    checkAcceptablePrice(marketFeed, prices, epochTime);

    MarketFeedConfig storage m = marketFeeds_config[marketFeed];
    require(prices.length >= m.minRequiredSources, "Not enough sources");

    // 512-bit vector to keep track of sources.
    // Each ID goes into a single slot in the 2 block vector of [bloom1, bloom0].
    // IDs are in [1, 511].
    uint256 bloom1 = 0;
    uint256 bloom0 = 0;

    for (uint i = 0; i < prices.length; i++) {
      // Check that signer is authorized.
      address signer = recover(marketIds[i], prices[i], epochTime[i], signatures[i]);
      bytes32 source = m.signerToSource[signer];
      require(source != 0, "Signature by invalid source");
      require(m.sourceToMarketId[source] == marketIds[i], "Invalid market ID for source");

      emit SourceReported(marketFeed, source, signer, epochTime[i]);

      uint16 sourceId = m.sourceToId[m.signerToSource[signer]] - 1;
      if (sourceId <= 255) {
        uint8 slot = uint8(sourceId); // Lower byte
        require((bloom0 >> slot) % 2 == 0, "Source already signed");
        bloom0 += uint256(2) ** slot;
      } else {
        uint8 slot = uint8(sourceId >> 8); // Upper byte
        require((bloom1 >> slot) % 2 == 0, "Source already signed");
        bloom1 += uint256(2) ** slot;
      }
    }

    acceptPrice(marketFeed, marketIds, prices, epochTime);
  }

  function getPrice(bytes32 marketFeed) external view readersOnly(marketFeed) returns (uint256) {
    require(marketFeeds_data[marketFeed].price > 0, "Invalid price feed");
    return marketFeeds_data[marketFeed].price;
  }

  function getPriceAndTime(bytes32 marketFeed) external view readersOnly(marketFeed)
      returns (uint256 price, uint256 blockTime, uint256 epochTime) {
    MarketFeedData storage m = marketFeeds_data[marketFeed];
    require(m.price > 0, "Invalid price feed");
    return (m.price, m.blockTime, m.epochTime);
  }

  // function getRawPrices(bytes32 marketFeed) external view readersOnly(marketFeed) returns (uint256[] memory) {
  //   require(marketFeeds_data[marketFeed].price > 0, "Invalid price feed");
  //   return marketFeeds_data[marketFeed].rawPrices;
  // }

  // Initializes a new MarketFeed with the sender as the sole manager and reader.
  function createMarketFeed(bytes32 name, bytes32 marketId, uint256 minRequiredSources) external {
    require(marketFeeds_config[name].minRequiredSources == 0, "MarketFeed already exists");
    require(minRequiredSources > 0, "Must require  > 0 sources");
    marketFeeds_config[name].marketId = marketId;
    marketFeeds_config[name].managers[msg.sender] = true;
    marketFeeds_config[name].readers[msg.sender] = true;
    marketFeeds_config[name].minRequiredSources = minRequiredSources;

    emit MarketFeedCreation(name, marketId, minRequiredSources, msg.sender);
  }

  function addManager(bytes32 marketFeed, address m) external managersOnly(marketFeed) {
    marketFeeds_config[marketFeed].managers[m] = true;

    emit ManagerAddition(msg.sender, marketFeed, m);
  }

  function removeManager(bytes32 marketFeed, address m) external managersOnly(marketFeed) {
    marketFeeds_config[marketFeed].managers[m] = false;

    emit ManagerRemoval(msg.sender, marketFeed, m);
  }

  function addSource(bytes32 marketFeed, bytes32 src, bytes32 sourceMarketId) public managersOnly(marketFeed) {
    require(src != 0, "Source cannot be 0");
    MarketFeedConfig storage m = marketFeeds_config[marketFeed];
    require(m.sourceToId[src] == 0, "Source already exists");
    require(m.lastSourceId < 512, "Reached max of 511 sources");
    m.lastSourceId++;
    m.sourceToId[src] = marketFeeds_config[marketFeed].lastSourceId;
    m.idToSource[m.lastSourceId] = src;
    m.sourceToMarketId[src] = sourceMarketId;

    emit SourceAddition(marketFeed, src, sourceMarketId, msg.sender);
  }

  function removeSource(bytes32 marketFeed, bytes32 src) public managersOnly(marketFeed) {
    MarketFeedConfig storage m = marketFeeds_config[marketFeed];

    // Reassign source in last slot to take the removed source's ID.
    uint16 idToReassign = m.sourceToId[src];
    bytes32 lastSource = m.idToSource[m.lastSourceId];

    m.sourceToId[src] = 0;
    m.idToSource[m.lastSourceId] = 0;

    m.sourceToId[lastSource] = idToReassign;
    m.idToSource[idToReassign] = lastSource;

    // Delete source's signers.
    address[] storage signersToDelete = m.sourceToSigners[src];
    for (uint i = 0; i < signersToDelete.length; i++) {
      address signer = signersToDelete[i];
      delete m.signerToSource[signer];
    }
    delete m.sourceToSigners[src];

    m.lastSourceId--;

    emit SourceRemoval(marketFeed, src, msg.sender);
  }

  function addSigner(bytes32 marketFeed, bytes32 src, address signer) public managersOnly(marketFeed) {
    require(signer != address(0), "No signer 0");

    MarketFeedConfig storage m = marketFeeds_config[marketFeed];
    require(m.sourceToId[src] != 0, "Invalid source for marketFeed");
    m.signerToSource[signer] = src;
    m.sourceToSigners[src].push(signer);

    emit SignerAddition(marketFeed, src, signer, msg.sender);
  }

  function removeSigner(bytes32 marketFeed, address signer) external managersOnly(marketFeed) {
    MarketFeedConfig storage m = marketFeeds_config[marketFeed];
    bytes32 src = m.signerToSource[signer];
    address[] storage sourcesSigners = m.sourceToSigners[src];

    for (uint i = 0; i < sourcesSigners.length; i++) {
      if (sourcesSigners[i] == signer) {
        sourcesSigners[i] = sourcesSigners[sourcesSigners.length - 1];
        sourcesSigners.length--;
        break;
      }
    }
    delete m.signerToSource[signer];

    emit SignerRemoval(marketFeed, src, signer, msg.sender);
  }

  // Convenience function for adding sources and signers at the same time.
  // Adds source if it doesn't exist yet.
  function batchAddSourceAndSigner(
    bytes32 marketFeed,
    bytes32[] calldata sources,
    bytes32[] calldata sourceMarketIds,
    address[] calldata signers
  ) external managersOnly(marketFeed) {
    require(sources.length == sourceMarketIds.length && sources.length == signers.length, "Input lists must be of equal length");
    for (uint i = 0; i < sources.length; i++) {
      if (marketFeeds_config[marketFeed].sourceToId[sources[i]] == 0) {
        addSource(marketFeed, sources[i], sourceMarketIds[i]);
      }
      addSigner(marketFeed, sources[i], signers[i]);
    }
  }

  function setMinRequiredSources(bytes32 marketFeed, uint256 newMin) external managersOnly(marketFeed) {
    require(newMin > 0, "min must be positive");
    marketFeeds_config[marketFeed].minRequiredSources = newMin;

    emit MinRequiredSourcesUpdated(marketFeed, newMin, msg.sender);
  }

  function addReader(bytes32 marketFeed, address r) external managersOnly(marketFeed) {
    require (r != address(0), "No contract 0");
    marketFeeds_config[marketFeed].readers[r] = true;
  }

  function removeReader(bytes32 marketFeed, address r) external managersOnly(marketFeed) {
    marketFeeds_config[marketFeed].readers[r] = false;
  }

  /*********************** Internal methods *******************/

  function checkAcceptablePrice(bytes32 marketFeed, uint256[] memory prices, uint256[] memory epochTime) internal view {
    uint256 prevPrice = 0;
    uint256 lastUpdatedTime = marketFeeds_data[marketFeed].epochTime;

    for (uint i = 0; i < prices.length; i++) {
        require(epochTime[i] > lastUpdatedTime, "Price must be newer than last");
        require(epochTime[i] < block.timestamp, "Price cannot be after blocktime");
        require(prices[i] >= prevPrice, "List must be sorted");
        prevPrice = prices[i];
    }
  }

  // Recovers the signer of the marketFeed price data.
  function recover(bytes32 marketId, uint256 price, uint256 time, bytes memory signature) internal pure returns (address) {
    (bytes32 r, bytes32 s, uint8 v) = abi.decode(signature, (bytes32, bytes32, uint8));
    return ecrecover(
        keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(price, time, marketId)))),
        v, r, s
    );
  }

  // @dev This function was split out of `post()` due to stack variable count limitations.
  function acceptPrice(bytes32 marketFeed, bytes32[] memory marketIds, uint256[] memory prices, uint256[] memory epochTime) internal {
    // Set price to median.
    uint256 medianPrice;
    uint256 midPoint = prices.length >> 1;
    if (prices.length % 2 == 0) {
      medianPrice = (prices[midPoint - 1] + prices[midPoint]) / 2;
    } else {
      medianPrice = prices[prices.length >> 1];
    }
    marketFeeds_data[marketFeed].price = medianPrice;

    marketFeeds_data[marketFeed].blockTime = block.timestamp;
    marketFeeds_data[marketFeed].epochTime = uint256(epochTime[prices.length >> 1]);

    emit MedianPriceWritten(marketFeed, marketFeeds_data[marketFeed].price, marketFeeds_data[marketFeed].blockTime, msg.sender);
  }
}
