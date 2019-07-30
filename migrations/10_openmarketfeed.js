const OpenMarketFeed = artifacts.require("OpenMarketFeed");

module.exports = function(deployer) {
  deployer.deploy(OpenMarketFeed);
};
