var HDWalletProvider = require ("@truffle/hdwallet-provider");

const Web3 = require ("web3");
const web3 = new Web3 ();

module.exports = {
  compilers: {
    solc: {
      version: "0.8.13",
      settings: {
        optimizer: {
          enabled: true,
          runs: 20000
        }
      }
    }
  },
  networks: {
    mumbai: {
      provider: function ()
        {
          return new HDWalletProvider ({
            privateKeys: [process.env.PRIVKEY],
            providerOrUrl: "https://rpc.ankr.com/polygon_mumbai"
          });
        },
      network_id: 80001,
      confirmations: 2,
      timeoutBlocks: 200,
      maxFeePerGas: web3.utils.toWei ('50', 'gwei'),
      maxPriorityFeePerGas: web3.utils.toWei ('35', 'gwei'),
      forwarder: "0x69015912AA33720b842dCD6aC059Ed623F28d9f7"
    },
    polygon: {
      provider: function ()
        {
          return new HDWalletProvider ({
            privateKeys: [process.env.PRIVKEY],
            providerOrUrl: "https://polygon-rpc.com/"
          });
        },
      network_id: 137,
      confirmations: 2,
      timeoutBlocks: 200,
      maxFeePerGas: web3.utils.toWei ('100', 'gwei'),
      maxPriorityFeePerGas: web3.utils.toWei ('35', 'gwei'),
      forwarder: "0xf0511f123164602042ab2bCF02111fA5D3Fe97CD"
    },
  },
  plugins: ["solidity-coverage"]
};
