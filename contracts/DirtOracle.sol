pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2; // Needed for using bytes[] parameter type.

contract DirtOracle {

  // Anyone can create a new DataFeed with `createDataFeed()`.
  // Only the managers of a DataFeed can edit parameters (whitelists and config) of the dataFeed.
  // Anyone can post updates to the dataFeed data with `post()`, but the data is only accepted if it meets the dataFeed's configured criteria.
  struct DataFeedConfig {
    mapping (bytes32 => bytes32) sourceToDataId;

    // Whitelists, all editable only by managers
    mapping (bytes32 => address[]) sourceToSigners;
    mapping (address => bytes32) signerToSource;

    mapping (bytes32 => uint16) sourceToId;
    mapping (uint16 => bytes32) idToSource;
    // Source IDs are assigned in incrementing order in a packed manner in the range [1, 511].
    // If a source is deleted, the last source is reassigned its ID and the last source ID is freed up.
    uint16 lastSourceId;

    uint16 minRequiredSources;

    mapping (address => bool) readers;
    mapping (address => bool) managers;

    bool isFree; // If True, any address may read from this Datafeed at no cost.
  }

  struct DataFeedData {
    // Last accepted data
    int128 value;
    uint256 blockTime;
    uint256 epochTime;
  }

  /*************** State attributes ***************/

  // A map from dataFeed name to DataFeed.
  mapping (bytes32 => DataFeedConfig) public dataFeeds_config;
  mapping (bytes32 => DataFeedData) internal dataFeeds_data;

  /*************** Emitted Events *****************/

  // when a data feed is created
  event DataFeedCreation(
    address indexed manager,
    bytes32 indexed dataFeed,
    uint16 minRequiredSources
  );

  // when an existing manager adds a new manager
  event ManagerAddition(
    address indexed manager,
    bytes32 indexed dataFeed,
    address indexed newManager
  );

  // when an existing manager removes a existing manager
  event ManagerRemoval(
    address indexed manager,
    bytes32 indexed dataFeed,
    address indexed firedManager
  );

  // when a source is added
  event SourceAddition(
    address indexed manager,
    bytes32 indexed dataFeed,
    bytes32 indexed source,
    bytes32 sourceDataId
  );

  // when a source is removed
  event SourceRemoval(
    address indexed manager,
    bytes32 indexed dataFeed,
    bytes32 indexed source
  );

  // when a signer is added
  event SignerAddition(
    address indexed manager,
    bytes32 indexed dataFeed,
    bytes32 indexed source,
    address signer
  );

  // when a signer is removed
  event SignerRemoval(
    address indexed manager,
    bytes32 indexed dataFeed,
    bytes32 indexed source,
    address signer
  );

  // when a reader is added
  event ReaderAddition(
    address indexed manager,
    bytes32 indexed dataFeed,
    address indexed newReader
  );

  // when a reader is removed
  event ReaderRemoval(
    address indexed manager,
    bytes32 indexed dataFeed,
    address indexed firedReader
  );

  // when min required sources is updated
  event MinRequiredSourcesUpdated(
    address indexed manager,
    bytes32 indexed dataFeed,
    uint16 newMin
  );

  event IsFreeUpdated(
    address manager,
    bytes32 dataFeed,
    bool isFree
  );

  // when a valid source reports a value
  event SignerReported(
    bytes32 indexed dataFeed,
    address indexed signerAddress,
    int128 value,
    uint256 epochTime
  );

  // when contract writes a median value
  event MedianValueWritten(
    address indexed reporterAddress,
    bytes32 indexed dataFeed,
    int128 value,
    uint256 epochTime,
    address[] signerAddresses,
    int128[] signerValues
  );

  /*********************** Modifiers *******************/

  modifier managersOnly(bytes32 dataFeed) {
    require(dataFeeds_config[dataFeed].managers[msg.sender], 'not a manager');
    _;
  }

  modifier readersOnly(bytes32 dataFeed) {
    DataFeedConfig storage m = dataFeeds_config[dataFeed];
    if (!m.isFree) {
      require(
        dataFeeds_config[dataFeed].readers[msg.sender],
        "unauthorized reader"
      );
    }
    _;
  }

  /*********************** Public methods *******************/

  constructor() public {}

  /*********************** External methods *******************/

  // Posts a new sorted value list for a dataFeed.
  function post(bytes32 dataFeed, bytes32[] calldata dataIds, int128[] calldata values, uint256[] calldata epochTime,
      bytes[] calldata signatures) external {
    checkAcceptableValue(dataFeed, values, epochTime);

    DataFeedConfig storage m = dataFeeds_config[dataFeed];
    require(values.length >= m.minRequiredSources, "Not enough sources");

    // 512-bit vector to keep track of sources.
    // Each ID goes into a single slot in the 2 block vector of [bloom1, bloom0].
    // IDs are in [1, 511].
    uint256 bloom1 = 0;
    uint256 bloom0 = 0;

    address[] memory signers = new address[](values.length);

    for (uint i = 0; i < values.length; i++) {
      // Check that signer is authorized.
      address signer = recover(dataIds[i], values[i], epochTime[i], signatures[i]);
      signers[i] = signer;

      bytes32 source = m.signerToSource[signer];
      require(source != 0, "Signature by invalid source");
      require(m.sourceToDataId[source] == dataIds[i], "Invalid data ID for source");

      // emit SignerReported(dataFeed, signer, values[i], epochTime[i]);

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

    acceptValue(dataFeed, signers, values, epochTime);
  }

  function getValue(bytes32 dataFeed) external view readersOnly(dataFeed) returns (int128) {
    return dataFeeds_data[dataFeed].value;
  }

  function getValueAndTime(bytes32 dataFeed) external view readersOnly(dataFeed)
      returns (int128 value, uint256 blockTime, uint256 epochTime) {
    DataFeedData storage m = dataFeeds_data[dataFeed];
    return (m.value, m.blockTime, m.epochTime);
  }

  // Initializes a new DataFeed with the sender as the sole manager and reader.
  function createDataFeed(
    bytes32 name,
    uint16 minRequiredSources,
    bool isFree
  )
    external
  {
    require(dataFeeds_config[name].minRequiredSources == 0, "DataFeed already exists");
    require(minRequiredSources < 512, "Must require  < 512 sources");
    dataFeeds_config[name].managers[msg.sender] = true;
    dataFeeds_config[name].readers[msg.sender] = true;
    dataFeeds_config[name].isFree = isFree;
    dataFeeds_config[name].minRequiredSources = minRequiredSources;

    emit DataFeedCreation(msg.sender, name, minRequiredSources);
  }

  function addManager(bytes32 dataFeed, address m) external managersOnly(dataFeed) {
    dataFeeds_config[dataFeed].managers[m] = true;

    emit ManagerAddition(msg.sender, dataFeed, m);
  }

  function removeManager(bytes32 dataFeed, address m) external managersOnly(dataFeed) {
    require(
      dataFeeds_config[dataFeed].managers[m],
      "Datafeed or Manager does not exist"
    );
    dataFeeds_config[dataFeed].managers[m] = false;

    emit ManagerRemoval(msg.sender, dataFeed, m);
  }

  function addSource(bytes32 dataFeed, bytes32 src, bytes32 sourceDataId) public managersOnly(dataFeed) {
    require(src != 0, "Source cannot be 0");
    require(sourceDataId != 0, "sourceDataId cannot be 0");
    DataFeedConfig storage m = dataFeeds_config[dataFeed];
    require(m.minRequiredSources > 0, "Datafeed does not exist");
    require(m.sourceToId[src] == 0, "Source already exists");
    require(m.lastSourceId < 512, "Reached max of 511 sources");
    m.lastSourceId++;
    m.sourceToId[src] = dataFeeds_config[dataFeed].lastSourceId;
    m.idToSource[m.lastSourceId] = src;
    m.sourceToDataId[src] = sourceDataId;

    emit SourceAddition(msg.sender, dataFeed, src, sourceDataId);
  }

  function removeSource(bytes32 dataFeed, bytes32 src) public managersOnly(dataFeed) {
    DataFeedConfig storage m = dataFeeds_config[dataFeed];

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

    emit SourceRemoval(msg.sender, dataFeed, src);
  }

  function addSigner(bytes32 dataFeed, bytes32 src, address signer) public managersOnly(dataFeed) {
    require(signer != address(0), "No signer 0");

    DataFeedConfig storage m = dataFeeds_config[dataFeed];
    require(m.sourceToId[src] != 0, "Invalid source for dataFeed");
    require(m.signerToSource[signer] == 0, "Signer already added to this Source");
    require(
      m.sourceToSigners[src].length <= 20,
      "Source cannot have more than 20 Signers"
    );
    m.signerToSource[signer] = src;
    m.sourceToSigners[src].push(signer);

    emit SignerAddition(msg.sender, dataFeed, src, signer);
  }

  function removeSigner(bytes32 dataFeed, address signer) external managersOnly(dataFeed) {
    DataFeedConfig storage m = dataFeeds_config[dataFeed];
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

    emit SignerRemoval(msg.sender, dataFeed, src, signer);
  }

  // Convenience function for adding sources and signers at the same time.
  // Adds source if it doesn't exist yet.
  function batchAddSourceAndSigner(
    bytes32 dataFeed,
    bytes32[] calldata sources,
    bytes32[] calldata sourceDataIds,
    address[] calldata signers
  ) external managersOnly(dataFeed) {
    require(sources.length == sourceDataIds.length && sources.length == signers.length, "Input lists must be of equal length");
    require(sources.length != 0, "Source and Signer lists should not be empty");
    require(
      dataFeeds_config[dataFeed].minRequiredSources != 0,
      "Datafeed does not exist"
    );
    for (uint i = 0; i < sources.length; i++) {
      if (dataFeeds_config[dataFeed].sourceToId[sources[i]] == 0) {
        addSource(dataFeed, sources[i], sourceDataIds[i]);
      }
      addSigner(dataFeed, sources[i], signers[i]);
    }
  }

  function setMinRequiredSources(bytes32 dataFeed, uint16 newMin) external managersOnly(dataFeed) {
    require(newMin > 0, "min must be positive");
    require(newMin < 512, "min must be less than 512");
    dataFeeds_config[dataFeed].minRequiredSources = newMin;

    emit MinRequiredSourcesUpdated(msg.sender, dataFeed, newMin);
  }

  function setIsFree(bytes32 dataFeed, bool isFree) external managersOnly(dataFeed) {
    dataFeeds_config[dataFeed].isFree = isFree;
    emit IsFreeUpdated(msg.sender, dataFeed, isFree);
  }

  function addReader(bytes32 dataFeed, address r) external managersOnly(dataFeed) {
    require (r != address(0), "No contract 0");
    dataFeeds_config[dataFeed].readers[r] = true;

    emit ReaderAddition(msg.sender, dataFeed, r);
  }

  function removeReader(bytes32 dataFeed, address r) external managersOnly(dataFeed) {
    require(r != address(0), "Reader address should not be 0");
    dataFeeds_config[dataFeed].readers[r] = false;

    emit ReaderRemoval(msg.sender, dataFeed, r);
  }

  /*********************** Internal methods *******************/

  function checkAcceptableValue(bytes32 dataFeed, int128[] memory values, uint256[] memory epochTime) internal view {
    int128 prevValue = values[0];
    uint256 lastUpdatedTime = dataFeeds_data[dataFeed].epochTime;

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

  // Recovers the signer of the dataFeed data.
  function recover(
    bytes32 dataId,
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
            keccak256(abi.encodePacked(value, time, dataId))
          )
        ),
        v, r, s
    );
  }

  // @dev This function was split out of `post()` due to stack variable count limitations.
  function acceptValue(
    bytes32 dataFeed,
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

    dataFeeds_data[dataFeed].value = medianValue;
    dataFeeds_data[dataFeed].epochTime = medianEpochTime;

    dataFeeds_data[dataFeed].blockTime = block.timestamp;

    emit MedianValueWritten(
      msg.sender,
      dataFeed,
      dataFeeds_data[dataFeed].value,
      dataFeeds_data[dataFeed].epochTime,
      signers,
      values
    );
  }
}
