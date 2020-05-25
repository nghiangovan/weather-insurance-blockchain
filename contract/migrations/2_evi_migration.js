let EviFactory = artifacts.require('EviFactory')
let Integers = artifacts.require('Integers')
let Strings = artifacts.require('Strings')

module.exports = async function(deployer) {
  // deployer.deploy(Integers).then(function() {
  //   return deployer.deploy(EviFactory, Integers.address)
  // })
  await deployer.deploy(Integers)
  await deployer.link(Integers, EviFactory)
  await deployer.deploy(EviFactory).then(async () => {
    // var factory = await EviFactory.deployed()
    // await factory.createEvi()
  })
}
