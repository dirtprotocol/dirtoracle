let helper = require("./test_helpers.js")

const OpenMarketFeed = artifacts.require('OpenMarketFeed')

contract("OpenMarketFeed", function (accounts) {

  let marketFeedName = web3.utils.toHex('Official ETH/USD')
  let marketName = web3.utils.toHex('ETH/USD') // OMC, Coinbase
  let altMarketName = web3.utils.toHex('ETH-USD') // Kraken
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

  createAbiEncodedSignature = async (price, timestamp, marketName, privateKey) => {
    let dataHash = web3.utils.soliditySha3(
      { t: 'uint256', v: price },
      { t: 'uint256', v: timestamp },
      { t: 'bytes32', v: marketName }
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
    omf = await OpenMarketFeed.deployed()
    await omf.createMarketFeed(marketFeedName, marketName, 1)
  })

  beforeEach(async () => {
    snapshot = await helper.snapshot(web3)
  })

  afterEach(async () => {
    await helper.revert(web3, snapshot.result)
  })

  context("With basic sources/signers", async () => {
    before(async () => {
      await omf.addSource(marketFeedName, web3.utils.toHex('OMC'), marketName)
      await omf.addSigner(marketFeedName, web3.utils.toHex('OMC'), OMC_ADDRESS)
      await omf.addSource(marketFeedName, web3.utils.toHex('Coinbase'), marketName)
      await omf.addSigner(marketFeedName, web3.utils.toHex('Coinbase'), COINBASE_ADDRESS)
      await omf.addSource(marketFeedName, web3.utils.toHex('Kraken'), altMarketName)
      await omf.addSigner(marketFeedName, web3.utils.toHex('Kraken'), KRAKEN_ADDRESS)

      await omf.addReader(marketFeedName, accounts[0])
    })

    it("post", async function () {
      let price = web3.utils.toWei('1');
      let timestamp = 123456789
      let abiEncodedSignature = await createAbiEncodedSignature(price, timestamp, marketName, OMC_KEY)
      await omf.post(marketFeedName, [marketName], [price], [timestamp], [abiEncodedSignature])
      let fetchedPrice = await omf.getPrice(marketFeedName)
      assert.equal(price, fetchedPrice)
    })

    it("duplicate market feed", async function () {
      await expectRevert(omf.createMarketFeed(marketFeedName, marketName, 1),
        'MarketFeed already exists');
    })

    it("even price list (median)", async function () {
      let priceOmc = web3.utils.toWei('200');
      let priceCoinbase = web3.utils.toWei('250');
      let timestampOmc = 123456789
      let timestampCoinbase = 123456790
      let abiEncodedSignatureOMC = await createAbiEncodedSignature(priceOmc, timestampOmc, marketName, OMC_KEY)
      let abiEncodedSignatureCoinbase = await createAbiEncodedSignature(priceCoinbase, timestampCoinbase, marketName, COINBASE_KEY)
      let tx = await omf.post(
        marketFeedName,
        [marketName, marketName],
        [priceOmc, priceCoinbase],
        [timestampOmc, timestampCoinbase],
        [abiEncodedSignatureOMC, abiEncodedSignatureCoinbase]
      )

      let res = await omf.getPriceAndTime(marketFeedName)
      let fetchedPrice = res[0]
      let fetchedTimestamp = res[2]

      if (tx.receipt.blockNumber % 2 === 0) {
        assert.equal(priceOmc, fetchedPrice)
        assert.equal(timestampOmc, fetchedTimestamp)
      } else {
        assert.equal(priceCoinbase, fetchedPrice)
        assert.equal(timestampCoinbase, fetchedTimestamp)
      }
    })

    it("odd price list (median)", async function () {
      let priceOmc = web3.utils.toWei('200');
      let priceCoinbase = web3.utils.toWei('250');
      let priceKraken = web3.utils.toWei('251');
      let timestampOmc = 123456789
      let timestampCoinbase = 123456790
      let timestampKraken = 123456800
      let abiEncodedSignatureOMC = await createAbiEncodedSignature(priceOmc, timestampOmc, marketName, OMC_KEY)
      let abiEncodedSignatureCoinbase = await createAbiEncodedSignature(priceCoinbase, timestampCoinbase, marketName, COINBASE_KEY)
      let abiEncodedSignatureKraken = await createAbiEncodedSignature(priceKraken, timestampKraken, altMarketName, KRAKEN_KEY)
      await omf.post(
        marketFeedName,
        [marketName, marketName, altMarketName],
        [priceOmc, priceCoinbase, priceKraken],
        [timestampOmc, timestampCoinbase, timestampKraken],
        [abiEncodedSignatureOMC, abiEncodedSignatureCoinbase, abiEncodedSignatureKraken]
      )

      let res = await omf.getPriceAndTime(marketFeedName)
      let fetchedPrice = res[0]
      let fetchedTimestamp = res[2]

      assert.equal(priceCoinbase, fetchedPrice)
      assert.equal(timestampCoinbase.toString(), fetchedTimestamp.toString())
    })

    it("unsorted price rejected", async function () {
      let priceOmc = web3.utils.toWei('200');
      let priceCoinbase = web3.utils.toWei('199');
      let timestamp = 123456789
      let abiEncodedSignatureOMC = await createAbiEncodedSignature(priceOmc, timestamp, marketName, OMC_KEY)
      let abiEncodedSignatureCoinbase = await createAbiEncodedSignature(priceCoinbase, timestamp, marketName, COINBASE_KEY)
      await expectRevert(omf.post(
        marketFeedName,
        [marketName, marketName],
        [priceOmc, priceCoinbase],
        [timestamp, timestamp],
        [abiEncodedSignatureOMC, abiEncodedSignatureCoinbase]
      ), "List must be sorted")
    })

    it("newer than block timestamp", async function () {
      let priceOmc = web3.utils.toWei('200')
      let priceCoinbase = web3.utils.toWei('201')
      let block = await web3.eth.getBlock(web3.eth.blockNumber)
      let timestamp = block.timestamp + 3000

      let abiEncodedSignatureOMC = await createAbiEncodedSignature(
        priceOmc, timestamp, marketName, OMC_KEY
      )
      let abiEncodedSignatureCoinbase = await createAbiEncodedSignature(
        priceCoinbase, timestamp, marketName, COINBASE_KEY
      )
      await expectRevert(omf.post(
        marketFeedName,
        [marketName, marketName],
        [priceOmc, priceCoinbase],
        [timestamp, timestamp],
        [abiEncodedSignatureOMC, abiEncodedSignatureCoinbase]
      ), "Price timestamp cannot be more than 5 minutes after blocktime")
    })

    it("slightly newer than block timestamp", async function () {
      let price = web3.utils.toWei('200')
      let block = await web3.eth.getBlock(web3.eth.blockNumber)
      let timestamp = block.timestamp + 295

      let abiEncodedSignatureOMC = await createAbiEncodedSignature(
        price, timestamp, marketName, OMC_KEY
      )
      omf.post(
        marketFeedName,
        [ marketName ],
        [ price ],
        [ timestamp ],
        [ abiEncodedSignatureOMC ]
      )
      let fetchedPrice = await omf.getPrice(marketFeedName)
      assert.equal(price, fetchedPrice)
    })

    it("older than last price", async function () {
      let priceOmc = web3.utils.toWei('200');
      let timestamp = 123456789
      let abiEncodedSignatureOMC = await createAbiEncodedSignature(priceOmc, timestamp, marketName, OMC_KEY)
      await omf.post(
        marketFeedName,
        [marketName],
        [priceOmc],
        [timestamp],
        [abiEncodedSignatureOMC]
      )

      timestamp = 123456788
      abiEncodedSignatureOMC = await createAbiEncodedSignature(priceOmc, timestamp, marketName, OMC_KEY)
      await expectRevert(omf.post(
        marketFeedName,
        [marketName],
        [priceOmc],
        [timestamp],
        [abiEncodedSignatureOMC]
      ), "Price must be newer than last")
    })

    it("price not set yet", async function () {
      await expectRevert(omf.getPrice(marketFeedName), "Invalid price feed")
    })

    it("reject source after removal ", async function () {
      await omf.removeSource(marketFeedName, web3.utils.toHex('OMC'))

      let price = web3.utils.toWei('1');
      let timestamp = 123456789
      let abiEncodedSignature = await createAbiEncodedSignature(price, timestamp, marketName, OMC_KEY)
      await expectRevert(omf.post(marketFeedName, [marketName], [price], [timestamp], [abiEncodedSignature]), "Signature by invalid source")
    })

    it("duplicate source post", async function () {
      let priceOmc = web3.utils.toWei('200');
      let priceOmc2 = web3.utils.toWei('250');
      let timestamp = 123456789
      let abiEncodedSignatureOMC = await createAbiEncodedSignature(priceOmc, timestamp, marketName, OMC_KEY)
      let abiEncodedSignatureOMC2 = await createAbiEncodedSignature(priceOmc2, timestamp, marketName, OMC_KEY)
      await expectRevert(omf.post(
        marketFeedName,
        [marketName, marketName],
        [priceOmc, priceOmc2],
        [timestamp, timestamp],
        [abiEncodedSignatureOMC, abiEncodedSignatureOMC2]
      ), "Source already signed")
    })

    it("reject signer after removal ", async function () {
      await omf.removeSigner(marketFeedName, OMC_ADDRESS)

      let price = web3.utils.toWei('1');
      let timestamp = 123456789
      let abiEncodedSignature = await createAbiEncodedSignature(price, timestamp, marketName, OMC_KEY)
      await expectRevert(omf.post(marketFeedName, [marketName], [price], [timestamp], [abiEncodedSignature]), "Signature by invalid source")
    })

    it("min required sources not met", async function () {
      await omf.setMinRequiredSources(marketFeedName, 2)

      let price = web3.utils.toWei('1');
      let timestamp = 123456789
      let abiEncodedSignature = await createAbiEncodedSignature(price, timestamp, marketName, OMC_KEY)
      await expectRevert(omf.post(marketFeedName, [marketName], [price], [timestamp], [abiEncodedSignature]), "Not enough sources")
    })

    it("reject reader after removal ", async function () {
      await omf.removeReader(marketFeedName, accounts[0])
      await expectRevert(omf.getPrice(marketFeedName), "unauthorized reader")
    })
  })

  it("batch add source and signer", async function () {
    await omf.batchAddSourceAndSigner(marketFeedName, [
      web3.utils.toHex('OMC'),
      web3.utils.toHex('Coinbase'),
      web3.utils.toHex('Kraken')
    ], [
        marketName,
        marketName,
        altMarketName
      ], [
        OMC_ADDRESS,
        COINBASE_ADDRESS,
        KRAKEN_ADDRESS
      ])
    await omf.addReader(marketFeedName, accounts[0])

    let priceOmc = web3.utils.toWei('200');
    let priceCoinbase = web3.utils.toWei('250');
    let priceKraken = web3.utils.toWei('251');
    let timestamp = 123456789
    let abiEncodedSignatureOMC = await createAbiEncodedSignature(priceOmc, timestamp, marketName, OMC_KEY)
    let abiEncodedSignatureCoinbase = await createAbiEncodedSignature(priceCoinbase, timestamp, marketName, COINBASE_KEY)
    let abiEncodedSignatureKraken = await createAbiEncodedSignature(priceKraken, timestamp, altMarketName, KRAKEN_KEY)
    await omf.post(
      marketFeedName,
      [marketName, marketName, altMarketName],
      [priceOmc, priceCoinbase, priceKraken],
      [timestamp, timestamp, timestamp],
      [abiEncodedSignatureOMC, abiEncodedSignatureCoinbase, abiEncodedSignatureKraken]
    )

    let fetchedPrice = await omf.getPrice(marketFeedName)
    assert.equal(web3.utils.toWei('250'), fetchedPrice)
  })

  it("add duplicate source", async function () {
    await omf.addSource(marketFeedName, web3.utils.toHex('OMC'), marketName)
    await expectRevert(omf.addSource(marketFeedName, web3.utils.toHex('OMC'), marketName), "Source already exists")
  })

});
