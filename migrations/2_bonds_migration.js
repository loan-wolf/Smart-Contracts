const Bonds = artifacts.require("Bonds");


module.exports = async function (deployer, _network, addresses) {
  await deployer.deploy(
    Bonds,
    {from: addresses[0]}
  );

  const bonds = await Bonds.deployed(); 

};
