
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
