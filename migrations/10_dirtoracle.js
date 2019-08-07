const DirtOracle = artifacts.require("DirtOracle");

module.exports = function(deployer) {
  deployer.deploy(DirtOracle);
};
