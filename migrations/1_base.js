// SPDX-License-Identifier: MIT
// Copyright (C) 2022 Autonomous Worlds Ltd

const truffleContract = require ("@truffle/contract");
const { networks } = require ("../truffle-config.js");

const XayaDelegation = artifacts.require ("XayaDelegation");

const accountsData
    = require ("@xaya/eth-account-registry/build/contracts/XayaAccounts.json");
const XayaAccounts = truffleContract (accountsData);
XayaAccounts.setProvider (XayaDelegation.currentProvider);

module.exports = async function (deployer, network)
  {
    /* This script is for the real deployment.  Unit tests use custom deployment
       on a per-test basis as needed, so we want to skip deployment entirely
       for them.  */
    if (network === "test" || network === "soliditycoverage")
      return;

    const acc = await XayaAccounts.deployed ();

    await deployer.deploy (XayaDelegation, acc.address,
                           networks[network].forwarder);
  };
