let helper = require("./test_helpers.js")

const DirtOracle = artifacts.require('DirtOracle')

contract("DirtOracle", function (accounts) {

  let dataFeedName = web3.utils.toHex('Official ETH/USD')
  let dataName = web3.utils.toHex('ETH/USD') // OMC, Coinbase
  let altDataName = web3.utils.toHex('ETH-USD') // Kraken
  let omf
  let snapshot

  const OMC_ADDRESS = '0xA1B3457bdBd16A5Cf1b1D460C9A53F0276959BC8'
  const OMC_KEY = '0x77acd4b0d00c1a3bd466dc99423ef727c39b5420d837975291f0fc105ee854e0'
  const COINBASE_ADDRESS = '0xF44894B0FEFAcE96b54Ba369cAD8682F24ADBbBE'
  const COINBASE_KEY = '0x05c06301ebf4c48de49d47760b8f012392066974998f84cd0db5227df0a2e83e'
  const KRAKEN_ADDRESS = '0x522016DCC6dDf2079bA067775d71F2CcF6f95A67'
  const KRAKEN_KEY = '0xd929d585144a75f860586859e6d0587e2f4a35fa8bcad31575527362c8ace87b'

  expectRevert = async (tx, msg) => {
    const PREFIX = "VM Exception while processing transaction: revert ";
    try {
      await tx;
    } catch (e) {
      assert(e.message.includes(PREFIX + msg), "Expected error message " + msg +
        " but instead got " + e.message);
      return
    }
    throw 'Transaction should have rejected with message ' + msg;
  }

  createAbiEncodedSignature = async (value, timestamp, dataName, privateKey) => {
    let dataHash = web3.utils.soliditySha3(
      { t: 'int128', v: value },
      { t: 'uint256', v: timestamp },
      { t: 'bytes32', v: dataName }
    )
    let sig = await web3.eth.accounts.sign(
      dataHash,
      privateKey
    )
    let abiEncoded = web3.eth.abi.encodeParameters(
      ['bytes32', 'bytes32', 'uint8'],
      [sig.r, sig.s, sig.v]
    )
    return abiEncoded;
  }

  before(async () => {
    omf = await DirtOracle.deployed()
    await omf.createDataFeed(dataFeedName, 1, false)
  })

  beforeEach(async () => {
    snapshot = await helper.snapshot(web3)
  })

  afterEach(async () => {
    await helper.revert(web3, snapshot.result)
  })

  context("With basic sources/signers", async () => {
    before(async () => {
      await omf.addSource(dataFeedName, web3.utils.toHex('OMC'), dataName)
      await omf.addSigner(dataFeedName, web3.utils.toHex('OMC'), OMC_ADDRESS)
      await omf.addSource(dataFeedName, web3.utils.toHex('Coinbase'), dataName)
      await omf.addSigner(dataFeedName, web3.utils.toHex('Coinbase'), COINBASE_ADDRESS)
      await omf.addSource(dataFeedName, web3.utils.toHex('Kraken'), altDataName)
      await omf.addSigner(dataFeedName, web3.utils.toHex('Kraken'), KRAKEN_ADDRESS)

      await omf.addReader(dataFeedName, accounts[0])
    })

    it("post", async function () {
      let value = web3.utils.toWei('1');
      let timestamp = 123456789
      let abiEncodedSignature = await createAbiEncodedSignature(value, timestamp, dataName, OMC_KEY)
      await omf.post(dataFeedName, [dataName], [value], [timestamp], [abiEncodedSignature])
      let fetchedValue = await omf.getValue(dataFeedName)
      assert.equal(value, fetchedValue)
    })

    it("duplicate data feed", async function () {
      await expectRevert(omf.createDataFeed(dataFeedName, 1, false),
        'DataFeed already exists');
    })

    it("even value list (median)", async function () {
      let valueOmc = web3.utils.toWei('200');
      let valueCoinbase = web3.utils.toWei('250');
      let timestampOmc = 123456789
      let timestampCoinbase = 123456790
      let abiEncodedSignatureOMC = await createAbiEncodedSignature(valueOmc, timestampOmc, dataName, OMC_KEY)
      let abiEncodedSignatureCoinbase = await createAbiEncodedSignature(valueCoinbase, timestampCoinbase, dataName, COINBASE_KEY)
      let tx = await omf.post(
        dataFeedName,
        [dataName, dataName],
        [valueOmc, valueCoinbase],
        [timestampOmc, timestampCoinbase],
        [abiEncodedSignatureOMC, abiEncodedSignatureCoinbase]
      )

      let res = await omf.getValueAndTime(dataFeedName)
      let fetchedValue = res[0]
      let fetchedTimestamp = res[2]

      if (tx.receipt.blockNumber % 2 === 0) {
        assert.equal(valueOmc, fetchedValue)
        assert.equal(timestampOmc, fetchedTimestamp)
      } else {
        assert.equal(valueCoinbase, fetchedValue)
        assert.equal(timestampCoinbase, fetchedTimestamp)
      }
    })

    it("odd value list (median)", async function () {
      let valueOmc = web3.utils.toWei('200');
      let valueCoinbase = web3.utils.toWei('250');
      let valueKraken = web3.utils.toWei('251');
      let timestampOmc = 123456789
      let timestampCoinbase = 123456790
      let timestampKraken = 123456800
      let abiEncodedSignatureOMC = await createAbiEncodedSignature(valueOmc, timestampOmc, dataName, OMC_KEY)
      let abiEncodedSignatureCoinbase = await createAbiEncodedSignature(valueCoinbase, timestampCoinbase, dataName, COINBASE_KEY)
      let abiEncodedSignatureKraken = await createAbiEncodedSignature(valueKraken, timestampKraken, altDataName, KRAKEN_KEY)
      await omf.post(
        dataFeedName,
        [dataName, dataName, altDataName],
        [valueOmc, valueCoinbase, valueKraken],
        [timestampOmc, timestampCoinbase, timestampKraken],
        [abiEncodedSignatureOMC, abiEncodedSignatureCoinbase, abiEncodedSignatureKraken]
      )

      let res = await omf.getValueAndTime(dataFeedName)
      let fetchedValue = res[0]
      let fetchedTimestamp = res[2]

      assert.equal(valueCoinbase, fetchedValue)
      assert.equal(timestampCoinbase.toString(), fetchedTimestamp.toString())
    })

    it("unsorted value rejected", async function () {
      let valueOmc = web3.utils.toWei('200');
      let valueCoinbase = web3.utils.toWei('199');
      let timestamp = 123456789
      let abiEncodedSignatureOMC = await createAbiEncodedSignature(valueOmc, timestamp, dataName, OMC_KEY)
      let abiEncodedSignatureCoinbase = await createAbiEncodedSignature(valueCoinbase, timestamp, dataName, COINBASE_KEY)
      await expectRevert(omf.post(
        dataFeedName,
        [dataName, dataName],
        [valueOmc, valueCoinbase],
        [timestamp, timestamp],
        [abiEncodedSignatureOMC, abiEncodedSignatureCoinbase]
      ), "List must be sorted")
    })

    it("newer than block timestamp", async function () {
      let valueOmc = web3.utils.toWei('200')
      let valueCoinbase = web3.utils.toWei('201')
      let block = await web3.eth.getBlock(web3.eth.blockNumber)
      let timestamp = block.timestamp * 2

      let abiEncodedSignatureOMC = await createAbiEncodedSignature(
        valueOmc, timestamp, dataName, OMC_KEY
      )
      let abiEncodedSignatureCoinbase = await createAbiEncodedSignature(
        valueCoinbase, timestamp, dataName, COINBASE_KEY
      )
      await expectRevert(omf.post(
        dataFeedName,
        [dataName, dataName],
        [valueOmc, valueCoinbase],
        [timestamp, timestamp],
        [abiEncodedSignatureOMC, abiEncodedSignatureCoinbase]
      ), "Value timestamp cannot be more than 5 minutes after blocktime")
    })

    it("slightly newer than block timestamp", async function () {
      let value = web3.utils.toWei('200')
      let block = await web3.eth.getBlock(web3.eth.blockNumber)
      let timestamp = block.timestamp + 295

      let abiEncodedSignatureOMC = await createAbiEncodedSignature(
        value, timestamp, dataName, OMC_KEY
      )
      omf.post(
        dataFeedName,
        [ dataName ],
        [ value ],
        [ timestamp ],
        [ abiEncodedSignatureOMC ]
      )
      let fetchedValue = await omf.getValue(dataFeedName)
      assert.equal(value, fetchedValue)
    })

    it("older than last value", async function () {
      let valueOmc = web3.utils.toWei('200');
      let timestamp = 123456789
      let abiEncodedSignatureOMC = await createAbiEncodedSignature(valueOmc, timestamp, dataName, OMC_KEY)
      await omf.post(
        dataFeedName,
        [dataName],
        [valueOmc],
        [timestamp],
        [abiEncodedSignatureOMC]
      )

      timestamp = 123456788
      abiEncodedSignatureOMC = await createAbiEncodedSignature(valueOmc, timestamp, dataName, OMC_KEY)
      await expectRevert(omf.post(
        dataFeedName,
        [dataName],
        [valueOmc],
        [timestamp],
        [abiEncodedSignatureOMC]
      ), "Value must be newer than last")
    })

    it("reject source after removal ", async function () {
      await omf.removeSource(dataFeedName, web3.utils.toHex('OMC'))

      let value = web3.utils.toWei('1');
      let timestamp = 123456789
      let abiEncodedSignature = await createAbiEncodedSignature(value, timestamp, dataName, OMC_KEY)
      await expectRevert(omf.post(dataFeedName, [dataName], [value], [timestamp], [abiEncodedSignature]), "Signature by invalid source")
    })

    it("duplicate source post", async function () {
      let valueOmc = web3.utils.toWei('200');
      let valueOmc2 = web3.utils.toWei('250');
      let timestamp = 123456789
      let abiEncodedSignatureOMC = await createAbiEncodedSignature(valueOmc, timestamp, dataName, OMC_KEY)
      let abiEncodedSignatureOMC2 = await createAbiEncodedSignature(valueOmc2, timestamp, dataName, OMC_KEY)
      await expectRevert(omf.post(
        dataFeedName,
        [dataName, dataName],
        [valueOmc, valueOmc2],
        [timestamp, timestamp],
        [abiEncodedSignatureOMC, abiEncodedSignatureOMC2]
      ), "Source already signed")
    })

    it("reject signer after removal ", async function () {
      await omf.removeSigner(dataFeedName, OMC_ADDRESS)

      let value = web3.utils.toWei('1');
      let timestamp = 123456789
      let abiEncodedSignature = await createAbiEncodedSignature(value, timestamp, dataName, OMC_KEY)
      await expectRevert(omf.post(dataFeedName, [dataName], [value], [timestamp], [abiEncodedSignature]), "Signature by invalid source")
    })

    it("min required sources not met", async function () {
      await omf.setMinRequiredSources(dataFeedName, 2)

      let value = web3.utils.toWei('1');
      let timestamp = 123456789
      let abiEncodedSignature = await createAbiEncodedSignature(value, timestamp, dataName, OMC_KEY)
      await expectRevert(omf.post(dataFeedName, [dataName], [value], [timestamp], [abiEncodedSignature]), "Not enough sources")
    })

    it("change whether reads are free", async function () {
      await omf.setIsFree(dataFeedName, true)
      await omf.removeReader(dataFeedName, accounts[0])
      await omf.getValue(dataFeedName)
    })

    it("reject reader after removal", async function () {
      await omf.removeReader(dataFeedName, accounts[0])
      await expectRevert(omf.getValue(dataFeedName), "unauthorized reader")
    })

    it("revert if manager doesn't exist", async function () {
      await expectRevert(
        omf.removeManager(dataFeedName, accounts[5]),
        "Datafeed or Manager does not exist"
      )
    })
  })

  it("batch add source and signer", async function () {
    await omf.batchAddSourceAndSigner(dataFeedName, [
      web3.utils.toHex('OMC'),
      web3.utils.toHex('Coinbase'),
      web3.utils.toHex('Kraken')
    ], [
        dataName,
        dataName,
        altDataName
      ], [
        OMC_ADDRESS,
        COINBASE_ADDRESS,
        KRAKEN_ADDRESS
      ])
    await omf.addReader(dataFeedName, accounts[0])

    let valueOmc = web3.utils.toWei('200');
    let valueCoinbase = web3.utils.toWei('250');
    let valueKraken = web3.utils.toWei('251');
    let timestamp = 123456789
    let abiEncodedSignatureOMC = await createAbiEncodedSignature(valueOmc, timestamp, dataName, OMC_KEY)
    let abiEncodedSignatureCoinbase = await createAbiEncodedSignature(valueCoinbase, timestamp, dataName, COINBASE_KEY)
    let abiEncodedSignatureKraken = await createAbiEncodedSignature(valueKraken, timestamp, altDataName, KRAKEN_KEY)
    await omf.post(
      dataFeedName,
      [dataName, dataName, altDataName],
      [valueOmc, valueCoinbase, valueKraken],
      [timestamp, timestamp, timestamp],
      [abiEncodedSignatureOMC, abiEncodedSignatureCoinbase, abiEncodedSignatureKraken]
    )

    let fetchedValue = await omf.getValue(dataFeedName)
    assert.equal(web3.utils.toWei('250'), fetchedValue)
  })

  it("add duplicate source", async function () {
    await omf.addSource(dataFeedName, web3.utils.toHex('OMC'), dataName)
    await expectRevert(omf.addSource(dataFeedName, web3.utils.toHex('OMC'), dataName), "Source already exists")
  })

});
