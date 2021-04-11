const Bonds = artifacts.require("Bonds");
const Payment = artifacts.require("ERC20PaymentStandard");
const Collateral = artifacts.require("ERC20CollateralPayment");
const MockDai = artifacts.require("tests/MockDai");




module.exports = async function (deployer, _network, addresses) {
  await deployer.deploy(
    Bonds,
    {from: addresses[0]}
  );
  
  const bonds = await Bonds.deployed(); 
  await deployer.deploy(
    Payment,
    bonds.address,
    {from: addresses[0]}
  );

  // const payment = await Payment.deployed();

  // await deployer.deploy(
  //   Collateral,
  //   bonds.address,
  //   {from: addresses[0]}
  // );

  // await deployer.deploy(
  //   MockDai,
  //   web3.utils.toWei('1000000','Ether'),
  //   {from: addresses[0]}
  // );

  const collateral = await Collateral.deployed();
};
