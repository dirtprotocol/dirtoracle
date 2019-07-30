
// fast-forwards the the EVM block.timestamp
let increaseTime = (web3, seconds) => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send({
      jsonrpc: "2.0",
      method: "evm_increaseTime",
      id: 12345,
      params: [seconds],
    }, (err, result) => {
      (err) ? reject(err) : resolve(result)
    })
  })
}

let snapshot = (web3) => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send({
      jsonrpc: "2.0",
      method: "evm_snapshot",
      id: 12345,
      params: [],
    }, (err, result) => {
      (err) ? reject(err) : resolve(result)
    })
  })
}

let revert = (web3, snapshotId) => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send({
      jsonrpc: "2.0",
      method: "evm_revert",
      id: 12345,
      params: [snapshotId],
    }, (err, result) => {
      (err) ? reject(err) : resolve(result)
    })
  })
}

module.exports = { increaseTime, snapshot, revert }