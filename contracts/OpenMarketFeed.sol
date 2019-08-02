pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2; // Needed for using bytes[] parameter type.

contract OpenMarketFeed {

  // Anyone can create a new MarketFeed with `createMarketFeed()`.
  // Only the managers of a MarketFeed can edit parameters (whitelists and config) of the marketFeed.
  // Anyone can post updates to the marketFeed data with `post()`, but the data is only accepted if it meets the marketFeed's configured criteria.
  struct MarketFeedConfig {
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

    uint16 minRequiredSources;
  }

  struct MarketFeedData {
    // Last accepted data
    int128 value;
    uint256 blockTime;
    uint256 epochTime;
  }

  /*************** State attributes ***************/

  // A map from marketFeed name to MarketFeed.
  mapping (bytes32 => MarketFeedConfig) internal marketFeeds_config;
  mapping (bytes32 => MarketFeedData) internal marketFeeds_data;

  /*************** Emitted Events *****************/

  // when a market feed is created
  event MarketFeedCreation(
    address indexed manager,
    bytes32 indexed marketFeed,
    uint16 minRequiredSources
  );

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
  );

  // when a source is added
  event SourceAddition(
    address indexed manager,
    bytes32 indexed marketFeed,
    bytes32 indexed source,
    bytes32 sourceMarketId
  );

  // when a source is removed
  event SourceRemoval(
    address indexed manager,
    bytes32 indexed marketFeed,
    bytes32 indexed source
  );

  // when a signer is added
  event SignerAddition(
    address indexed manager,
    bytes32 indexed marketFeed,
    bytes32 indexed source,
    address signer
  );

  // when a signer is removed
  event SignerRemoval(
    address indexed manager,
    bytes32 indexed marketFeed,
    bytes32 indexed source,
    address signer
  );

  // when a reader is added
  event ReaderAddition(
    address indexed manager,
    bytes32 indexed marketFeed,
    address indexed newReader
  );

  // when a reader is removed
  event ReaderRemoval(
    address indexed manager,
    bytes32 indexed marketFeed,
    address indexed firedReader
  );

  // when min required sources is updated
  event MinRequiredSourcesUpdated(
    address indexed manager,
    bytes32 indexed marketFeed,
    uint16 newMin
  );

  // when a valid source reports a value
  event SignerReported(
    bytes32 indexed marketFeed,
    address indexed signerAddress,
    int128 value,
    uint256 epochTime
  );

  // when contract writes a median value
  event MedianValueWritten(
    address indexed reporterAddress,
    bytes32 indexed marketFeed,
    int128 value,
    uint256 epochTime,
    address[] signerAddresses,
    int128[] signerValues
  );

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

  // Posts a new sorted value list for a marketFeed.
  function post(bytes32 marketFeed, bytes32[] calldata marketIds, int128[] calldata values, uint256[] calldata epochTime,
      bytes[] calldata signatures) external {
    checkAcceptableValue(marketFeed, values, epochTime);

    MarketFeedConfig storage m = marketFeeds_config[marketFeed];
    require(values.length >= m.minRequiredSources, "Not enough sources");

    // 512-bit vector to keep track of sources.
    // Each ID goes into a single slot in the 2 block vector of [bloom1, bloom0].
    // IDs are in [1, 511].
    uint256 bloom1 = 0;
    uint256 bloom0 = 0;

    address[] memory signers = new address[](values.length);

    for (uint i = 0; i < values.length; i++) {
      // Check that signer is authorized.
      address signer = recover(marketIds[i], values[i], epochTime[i], signatures[i]);
      signers[i] = signer;

      bytes32 source = m.signerToSource[signer];
      require(source != 0, "Signature by invalid source");
      require(m.sourceToMarketId[source] == marketIds[i], "Invalid market ID for source");

      // emit SignerReported(marketFeed, signer, values[i], epochTime[i]);

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

    acceptValue(marketFeed, signers, values, epochTime);
  }

  function getValue(bytes32 marketFeed) external view readersOnly(marketFeed) returns (int128) {
    return marketFeeds_data[marketFeed].value;
  }

  function getValueAndTime(bytes32 marketFeed) external view readersOnly(marketFeed)
      returns (int128 value, uint256 blockTime, uint256 epochTime) {
    MarketFeedData storage m = marketFeeds_data[marketFeed];
    return (m.value, m.blockTime, m.epochTime);
  }

  // Initializes a new MarketFeed with the sender as the sole manager and reader.
  function createMarketFeed(bytes32 name, uint16 minRequiredSources) external {
    require(marketFeeds_config[name].minRequiredSources == 0, "MarketFeed already exists");
    require(minRequiredSources < 512, "Must require  < 512 sources");
    marketFeeds_config[name].managers[msg.sender] = true;
    marketFeeds_config[name].readers[msg.sender] = true;
    marketFeeds_config[name].minRequiredSources = minRequiredSources;

    emit MarketFeedCreation(msg.sender, name, minRequiredSources);
  }

  function addManager(bytes32 marketFeed, address m) external managersOnly(marketFeed) {
    marketFeeds_config[marketFeed].managers[m] = true;

    emit ManagerAddition(msg.sender, marketFeed, m);
  }

  function removeManager(bytes32 marketFeed, address m) external managersOnly(marketFeed) {
    require(
      marketFeeds_config[marketFeed].managers[m],
      "Marketfeed or Manager does not exist"
    );
    marketFeeds_config[marketFeed].managers[m] = false;

    emit ManagerRemoval(msg.sender, marketFeed, m);
  }

  function addSource(bytes32 marketFeed, bytes32 src, bytes32 sourceMarketId) public managersOnly(marketFeed) {
    require(src != 0, "Source cannot be 0");
    require(sourceMarketId != 0, "sourceMarketId cannot be 0");
    MarketFeedConfig storage m = marketFeeds_config[marketFeed];
    require(m.minRequiredSources > 0, "Marketfeed does not exist");
    require(m.sourceToId[src] == 0, "Source already exists");
    require(m.lastSourceId < 512, "Reached max of 511 sources");
    m.lastSourceId++;
    m.sourceToId[src] = marketFeeds_config[marketFeed].lastSourceId;
    m.idToSource[m.lastSourceId] = src;
    m.sourceToMarketId[src] = sourceMarketId;

    emit SourceAddition(msg.sender, marketFeed, src, sourceMarketId);
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

    emit SourceRemoval(msg.sender, marketFeed, src);
  }

  function addSigner(bytes32 marketFeed, bytes32 src, address signer) public managersOnly(marketFeed) {
    require(signer != address(0), "No signer 0");

    MarketFeedConfig storage m = marketFeeds_config[marketFeed];
    require(m.sourceToId[src] != 0, "Invalid source for marketFeed");
    require(m.signerToSource[signer] == 0, "Signer already added to this Source");
    require(
      m.sourceToSigners[src].length <= 20,
      "Source cannot have more than 20 Signers"
    );
    m.signerToSource[signer] = src;
    m.sourceToSigners[src].push(signer);

    emit SignerAddition(msg.sender, marketFeed, src, signer);
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

    emit SignerRemoval(msg.sender, marketFeed, src, signer);
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
    require(sources.length != 0, "Source and Signer lists should not be empty");
    require(
      marketFeeds_config[marketFeed].minRequiredSources != 0,
      "Marketfeed does not exist"
    );
    for (uint i = 0; i < sources.length; i++) {
      if (marketFeeds_config[marketFeed].sourceToId[sources[i]] == 0) {
        addSource(marketFeed, sources[i], sourceMarketIds[i]);
      }
      addSigner(marketFeed, sources[i], signers[i]);
    }
  }

  function setMinRequiredSources(bytes32 marketFeed, uint16 newMin) external managersOnly(marketFeed) {
    require(newMin > 0, "min must be positive");
    require(newMin < 512, "min must be less than 512");
    marketFeeds_config[marketFeed].minRequiredSources = newMin;

    emit MinRequiredSourcesUpdated(msg.sender, marketFeed, newMin);
  }

  function addReader(bytes32 marketFeed, address r) external managersOnly(marketFeed) {
    require (r != address(0), "No contract 0");
    marketFeeds_config[marketFeed].readers[r] = true;

    emit ReaderAddition(msg.sender, marketFeed, r);
  }

  function removeReader(bytes32 marketFeed, address r) external managersOnly(marketFeed) {
    require(r != address(0), "Reader address should not be 0");
    marketFeeds_config[marketFeed].readers[r] = false;

    emit ReaderRemoval(msg.sender, marketFeed, r);
  }

  /*********************** Internal methods *******************/

  function checkAcceptableValue(bytes32 marketFeed, int128[] memory values, uint256[] memory epochTime) internal view {
    int128 prevValue = values[0];
    uint256 lastUpdatedTime = marketFeeds_data[marketFeed].epochTime;

    for (uint i = 0; i < values.length; i++) {
        require(epochTime[i] > lastUpdatedTime, "Value must be newer than last");
        require(
          epochTime[i] < (block.timestamp + 300),
          "Value timestamp cannot be more than 5 minutes after blocktime"
        );
        require(values[i] >= prevValue, "List must be sorted");
        prevValue = values[i];
    }
  }

  // Recovers the signer of the marketFeed data.
  function recover(
    bytes32 marketId,
    int128 value,
    uint256 time,
    bytes memory signature
  )
  internal pure returns (address)
  {
    (bytes32 r, bytes32 s, uint8 v) = abi.decode(
      signature, (bytes32, bytes32, uint8)
    );
    return ecrecover(
        keccak256(
          abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            keccak256(abi.encodePacked(value, time, marketId))
          )
        ),
        v, r, s
    );
  }

  // @dev This function was split out of `post()` due to stack variable count limitations.
  function acceptValue(
    bytes32 marketFeed,
    address[] memory signers,
    int128[] memory values,
    uint256[] memory epochTime
  ) internal {

    // Set value to median.
    int128 medianValue;
    uint256 medianEpochTime;
    uint256 midPoint = values.length >> 1;

    if (values.length % 2 == 0) {
      if (block.number % 2 == 0) {
        // lower values of middle two
        medianValue = values[midPoint - 1];
        medianEpochTime = epochTime[midPoint - 1];
      } else {
        // higher values of middle two
        medianValue = values[midPoint];
        medianEpochTime = epochTime[midPoint];
      }
    } else {
      medianValue = values[midPoint];
      medianEpochTime = epochTime[midPoint];
    }

    marketFeeds_data[marketFeed].value = medianValue;
    marketFeeds_data[marketFeed].epochTime = medianEpochTime;

    marketFeeds_data[marketFeed].blockTime = block.timestamp;

    emit MedianValueWritten(
      msg.sender,
      marketFeed,
      marketFeeds_data[marketFeed].value,
      marketFeeds_data[marketFeed].epochTime,
      signers,
      values
    );
  }
}
