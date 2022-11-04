// SPDX-License-Identifier: MIT
// Copyright (C) 2022 Autonomous Worlds Ltd

const truffleAssert = require ("truffle-assertions");
const truffleContract = require ("@truffle/contract");
const { time } = require ("@openzeppelin/test-helpers");

const wchiData = require ("@xaya/wchi/build/contracts/WCHI.json");
const WCHI = truffleContract (wchiData);
WCHI.setProvider (web3.currentProvider);

const policyData
    = require ("@xaya/eth-account-registry/build/contracts/TestPolicy.json");
const TestPolicy = truffleContract (policyData);
TestPolicy.setProvider (web3.currentProvider);
const accountsData
    = require ("@xaya/eth-account-registry/build/contracts/XayaAccounts.json");
const XayaAccounts = truffleContract (accountsData);
XayaAccounts.setProvider (web3.currentProvider);

const UnsafeForwarder = artifacts.require ("UnsafeForwarder");
const XayaDelegation = artifacts.require ("XayaDelegation");

const maxUint256 = "115792089237316195423570985008687907853269984665640564039457584007913129639935";

contract ("XayaDelegation", accounts => {
  let wchiSupply = accounts[0];
  let feeReceiver = accounts[0];
  let owner = accounts[0];
  let relayer = accounts[1];
  let kiloChi = accounts[2];

  let wchi, acc, fwd, del;
  let alice, bob;
  beforeEach (async () => {
    wchi = await WCHI.new ({from: wchiSupply});
    const policy = await TestPolicy.new ({from: feeReceiver});
    acc = await XayaAccounts.new (wchi.address, policy.address, {from: owner});
    fwd = await UnsafeForwarder.new ();
    del = await XayaDelegation.new (acc.address, fwd.address);

    /* The kiloChi account will have 1000 CHI-sat to begin with, and has
       the delegator account approved.  */
    await wchi.transfer (kiloChi, 1000, {from: wchiSupply});
    await wchi.approve (del.address, maxUint256, {from: kiloChi});

    /* To be able to sign messages, we create new and empty accounts
       explicitly.  */
    const wallet = web3.eth.accounts.wallet.create (2);
    alice = wallet[0];
    bob = wallet[1];
  });

  /* Helper method to send a meta transaction via our forwarder.  */
  const sendMetaTx = async (from, req) => {
    req = await req;
    await fwd.exec (req.to, req.data, from);
  };

  /* Helper method to construct the permit signature with the given wallet.  */
  const permitSignature = async (wallet) => {
    const msg = await acc.permitOperatorMessage (del.address);
    const sgn = await wallet.sign (msg);
    return sgn.signature;
  };

  /* ************************************************************************ */

  it ("rejects unexpected NFT transfers", async () => {
    const policy = await TestPolicy.new ({from: feeReceiver});
    const acc2 = await XayaAccounts.new (wchi.address, policy.address,
                                         {from: owner});

    const tokenId = await acc.tokenIdForName ("p", "x");
    await acc.register ("p", "x", {from: kiloChi});
    await acc2.register ("p", "x", {from: kiloChi});

    assert.equal (await acc.ownerOf (tokenId), kiloChi);
    assert.equal (await acc2.ownerOf (tokenId), kiloChi);

    await truffleAssert.reverts (
        acc.safeTransferFrom (kiloChi, del.address, tokenId, {from: kiloChi}),
        "cannot be received at the moment");
    await truffleAssert.reverts (
        acc2.safeTransferFrom (kiloChi, del.address, tokenId, {from: kiloChi}),
        "only Xaya names can be received");

    assert.equal (await acc.ownerOf (tokenId), kiloChi);
    assert.equal (await acc2.ownerOf (tokenId), kiloChi);
  });

  /* ************************************************************************ */

  it ("can registerFor with a meta transaction", async () => {
    /* The meta transaction should not cost any gas for the "from" account.  */
    const before = await web3.eth.getBalance (kiloChi);

    const sgn = await permitSignature (alice);
    await sendMetaTx (
        kiloChi,
        del.registerFor.request ("p", "domob", alice.address, sgn));

    const after = await web3.eth.getBalance (kiloChi);
    assert.equal (before, after);

    /* It should have taken the CHI fee from the sender account.  */
    assert.equal (await wchi.balanceOf (kiloChi), 1000 - 500);

    /* The name should exist and be owned by the target address.  */
    const tokenId = await acc.tokenIdForName ("p", "domob");
    assert.equal (await acc.ownerOf (tokenId), alice.address);

    /* The delegation contract should be approved.  */
    assert.isTrue (await acc.isApprovedForAll (alice.address, del.address));
  });

  it ("handles the registerFor fee payments correctly", async () => {
    /* Disapprove WCHI transfers.  This will then still allow registrations
       that are free, but others will revert.  */
    await wchi.approve (del.address, 0, {from: kiloChi});

    const sgn = await permitSignature (alice);
    await del.registerFor ("p", "x", alice.address, sgn, {from: kiloChi});
    await truffleAssert.reverts (
        del.registerFor ("p", "xx", alice.address, sgn, {from: kiloChi}),
        "allowance exceeded");

    assert.isTrue (await acc.exists ("p", "x"));
    assert.isFalse (await acc.exists ("p", "xx"));
  });

  it ("checks the registerFor signature and owner", async () => {
    const sgn = await permitSignature (alice);
    await del.registerFor ("p", "x", alice.address, sgn, {from: kiloChi});
    await truffleAssert.reverts (
        del.registerFor ("p", "y", bob.address, sgn, {from: kiloChi}),
        "signature did not match owner");

    assert.isTrue (await acc.exists ("p", "x"));
    assert.isFalse (await acc.exists ("p", "y"));
  });

  /* ************************************************************************ */

  it ("can take over a name", async () => {
    const sgn = await permitSignature (alice);
    await del.registerFor ("p", "domob", alice.address, sgn, {from: kiloChi});

    await truffleAssert.reverts (
        del.takeOverName ("p", "domob", {from: kiloChi}),
        "only the owner can request a take over");

    await sendMetaTx (alice.address, del.takeOverName.request ("p", "domob"));

    /* Alice should still have top-level access, which she can now refine
       as desired with meta transactions.  */
    await sendMetaTx (
        alice.address,
        del.grant.request ("p", "domob", ["sub"], alice.address, 100, false));
    await sendMetaTx (
        alice.address,
        del.revoke.request ("p", "domob", [], alice.address, false));

    const tokenId = await acc.tokenIdForName ("p", "domob");
    assert.equal (await acc.ownerOf (tokenId), del.address);
    assert.isTrue (await del.hasAccess ("p", "domob", ["sub", "foo"],
                                        alice.address, 100));
    assert.isFalse (await del.hasAccess ("p", "domob", ["sub", "foo"],
                                         alice.address, 101));
    assert.isFalse (await del.hasAccess ("p", "domob", ["other"],
                                         alice.address, 1));
  });

  /* ************************************************************************ */

  it ("checks access permissions for sending moves", async () => {
    await time.advanceBlock ();
    const start = (await time.latest ()).toNumber ();

    const sgn = await permitSignature (alice);
    await del.registerFor ("p", "x", alice.address, sgn, {from: kiloChi});
    await sendMetaTx (
        alice.address,
        del.grant.request ("p", "x", ["sub"], kiloChi, start + 100, false));

    const fcn
        = del.methods["sendHierarchicalMove(string,string,string[],string)"];

    time.increase (50);
    await truffleAssert.reverts (
        fcn ("p", "x", ["other"], "{}", {from: kiloChi}),
        "has no permission");
    await fcn ("p", "x", ["sub"], "{}", {from: kiloChi});
    await sendMetaTx (kiloChi, fcn.request ("p", "x", ["sub"], "{}"));
    time.increase (100);
    await truffleAssert.reverts (
        fcn ("p", "x", ["sub"], "{}", {from: kiloChi}),
        "has no permission");

    /* Two moves have been sent successfully, with
        {"sub":{}}
       each, costing 10 units in fees per move.  */
    assert.equal (await wchi.balanceOf (kiloChi), 1000 - 20);
  });

  it ("handles WCHI payment for moves correctly", async () => {
    const sgn = await permitSignature (alice);
    await del.registerFor ("p", "x", alice.address, sgn, {from: kiloChi});
    await sendMetaTx (
        alice.address,
        del.grant.request ("p", "x", [], kiloChi, maxUint256, false));

    const fcn
        = del.methods["sendHierarchicalMove(string,string,string[],string,"
                      + "uint256,uint256,address)"];

    await fcn ("p", "x", [], "{}", maxUint256, 42, alice.address,
               {from: kiloChi});
    await sendMetaTx (
        kiloChi,
        fcn.request ("p", "x", [], "{}", maxUint256, 42, alice.address));
    assert.equal (await wchi.balanceOf (kiloChi), 1000 - 2 * (2 + 42));
    assert.equal (await wchi.balanceOf (alice.address), 2 * 42);

    await wchi.approve (del.address, 0, {from: kiloChi});
    await truffleAssert.reverts (
        fcn ("p", "x", [], "{}", maxUint256, 42, owner, {from: kiloChi}),
        "allowance exceeded");
    await truffleAssert.reverts (
        sendMetaTx (
            kiloChi,
            fcn.request ("p", "x", [], "{}", maxUint256, 42, owner)),
        "reverted");
  });

  it ("sends the correct hierarchical moves", async () => {
    const sgn = await permitSignature (alice);
    await del.registerFor ("p", "x", alice.address, sgn, {from: kiloChi});
    await sendMetaTx (
        alice.address,
        del.grant.request ("p", "x", ["sub"], kiloChi, maxUint256, false));

    const fcn
        = del.methods["sendHierarchicalMove(string,string,string[],string)"];

    await truffleAssert.reverts (
        fcn ("p", "x", ["sub"], "null},\"other\":{\"foo\":42", {from: kiloChi}),
        "possible JSON injection attempt");

    const getAllMoves = async () => {
      return await acc.getPastEvents ("Move",
                                      {fromBlock: 0, toBlock: "latest"});
    };
    assert.deepEqual (await getAllMoves (), []);

    await sendMetaTx (
        kiloChi, fcn.request ("p", "x", ["sub"], "{\"foo\":42}"));
    const moves = await getAllMoves ();
    assert.equal (moves.length, 1);
    assert.equal (moves[0].args.ns, "p");
    assert.equal (moves[0].args.name, "x");
    assert.equal (moves[0].args.mv, "{\"sub\":{\"foo\":42}}");
    assert.equal (moves[0].args.mover, del.address);
  });

  /* ************************************************************************ */

  it ("gives convenience access to permission functions", async () => {
    await time.advanceBlock ();
    const start = (await time.latest ()).toNumber ();

    const sgn = await permitSignature (alice);
    await del.registerFor ("p", "x", alice.address, sgn, {from: kiloChi});
    const tokenId = await acc.tokenIdForName ("p", "x");
    assert.equal (await acc.ownerOf (tokenId), alice.address);

    const grant
        = del.methods["grant(string,string,string[],address,uint256,bool)"];
    const revoke = del.methods["revoke(string,string,string[],address,bool)"];
    const resetTree = del.methods["resetTree(string,string,string[])"];
    const expireTree = del.methods["expireTree(string,string,string[])"];

    await sendMetaTx (
        alice.address,
        grant.request ("p", "x", ["foo"], bob.address, start + 100, false));
    await sendMetaTx (
        bob.address,
        grant.request ("p", "x", ["foo", "bar"],
                        bob.address, start + 10, false));

    assert.isTrue (await del.hasAccess ("p", "x", ["foo", "baz"],
                                        bob.address, start + 50));

    await sendMetaTx (alice.address,
                      revoke.request ("p", "x", ["foo"], bob.address, false));

    assert.isFalse (await del.hasAccess ("p", "x", ["foo", "baz"],
                    bob.address, start + 50));
    assert.isTrue (await del.hasAccess ("p", "x", ["foo", "bar"],
                   bob.address, start + 5));

    time.increase (5);
    await sendMetaTx (kiloChi, expireTree.request ("p", "x", []));
    assert.isTrue (await del.permissionExists (
        tokenId, alice.address, ["foo", "bar"], bob.address, false));

    time.increase (10);
    await sendMetaTx (kiloChi, expireTree.request ("p", "x", []));
    assert.isFalse (await del.permissionExists (tokenId, alice.address, []));

    await sendMetaTx (
        alice.address,
        grant.request ("p", "x", ["foo"], bob.address, maxUint256, true));
    assert.isTrue (await del.permissionExists (tokenId, alice.address, []));
    await sendMetaTx (alice.address, resetTree.request ("p", "x", []));
    assert.isFalse (await del.permissionExists (tokenId, alice.address, []));
  });

  /* ************************************************************************ */

});
