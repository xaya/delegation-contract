// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

import { stringArray } from "./TestUtils.sol";
import "./UnsafeForwarder.sol";
import "../src/XayaDelegation.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@xaya/eth-account-registry/src/XayaAccounts.sol";
import "@xaya/eth-account-registry/test/TestPolicy.sol";
import "@xaya/eth-account-registry/test/TestToken.sol";

import { Test } from "forge-std/Test.sol";

contract XayaDelegationTest is Test
{

  address public immutable wchiSupply;
  address public immutable feeReceiver;
  address public immutable owner;
  address public immutable relayer;
  address public immutable kiloChi;

  uint256 public constant aliceKey = 123;
  address public immutable alice;

  uint256 public constant bobKey = 456;
  address public immutable bob;

  IERC20 public wchi;
  IXayaPolicy public policy;
  XayaAccounts public acc;
  UnsafeForwarder public fwd;
  XayaDelegation public del;

  constructor ()
  {
    wchiSupply = vm.addr (1);
    feeReceiver = wchiSupply;
    owner = wchiSupply;
    relayer = vm.addr (2);
    kiloChi = vm.addr (3);

    alice = vm.addr (aliceKey);
    bob = vm.addr (bobKey);

    vm.label (wchiSupply, "supply / fee receiver / owner");
    vm.label (relayer, "relayer");
    vm.label (kiloChi, "kiloChi");
    vm.label (alice, "alice");
    vm.label (bob, "bob");

    fwd = new UnsafeForwarder ();
  }

  function setUp () public
  {
    vm.prank (wchiSupply);
    wchi = new TestToken (10**20);
    vm.prank (feeReceiver);
    policy = new TestPolicy ();
    vm.prank (owner);
    acc = new XayaAccounts (wchi, policy);
    del = new XayaDelegation (acc, address (fwd));

    /* The kilChi account will have 1000 CHI-sat to begin with, and has
       the delegator account approved.  */
    vm.prank (wchiSupply);
    wchi.transfer (kiloChi, 1000);
    vm.prank (kiloChi);
    wchi.approve (address (del), type (uint256).max);
  }

  /**
   * @dev Constructs a permit signature from the given private key
   * (and associated address), allowing the delegation contract to
   * manage the name.
   */
  function permitSignature (uint256 key)
      internal view returns (bytes memory)
  {
    bytes memory message = acc.permitOperatorMessage (address (del));
    bytes32 hash = ECDSA.toEthSignedMessageHash (message);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign (key, hash);
    return abi.encodePacked (r, s, v);
  }

  /* ************************************************************************ */

  function test_unexpectedNftTransferRejected () public
  {
    vm.prank (owner);
    XayaAccounts acc2 = new XayaAccounts (wchi, policy);

    uint256 tokenId = acc.tokenIdForName ("p", "x");
    vm.startPrank (kiloChi);
    acc.register ("p", "x");
    acc2.register ("p", "x");

    vm.assertEq (acc.ownerOf (tokenId), kiloChi);
    vm.assertEq (acc2.ownerOf (tokenId), kiloChi);

    vm.expectRevert ("tokens cannot be received at the moment");
    acc.safeTransferFrom (kiloChi, address (del), tokenId);
    vm.expectRevert ("only Xaya names can be received");
    acc2.safeTransferFrom (kiloChi, address (del), tokenId);

    vm.assertEq (acc.ownerOf (tokenId), kiloChi);
    vm.assertEq (acc2.ownerOf (tokenId), kiloChi);
  }

  function test_registerForMetaTransaction () public
  {
    /* The meta transaction should not cost any gas for the "from" account.  */
    uint256 balBefore = kiloChi.balance;

    bytes memory sgn = permitSignature (aliceKey);
    fwd.exec (
        address (del),
        abi.encodeCall (del.registerFor, ("p", "domob", alice, sgn)),
        kiloChi);

    uint256 balAfter = kiloChi.balance;
    vm.assertEq (balBefore, balAfter);

    /* It should have taken the CHI fee from the sender account.  */
    vm.assertEq (wchi.balanceOf (kiloChi), 1000 - 500);

    /* The name should exist and be owned by the target address.  */
    uint256 tokenId = acc.tokenIdForName ("p", "domob");
    vm.assertEq (acc.ownerOf (tokenId), alice);

    /* The delegation contract should be approved.  */
    vm.assertTrue (acc.isApprovedForAll (alice, address (del)));
  }

  function test_registerForFeePayments () public
  {
    /* Disapprove WCHI transfers.  This will then still allow registrations
       that are free, but others will revert.  */
    vm.prank (kiloChi);
    wchi.approve (address (del), 0);

    bytes memory sgn = permitSignature (aliceKey);
    vm.prank (kiloChi);
    del.registerFor ("p", "x", alice, sgn);

    vm.expectRevert ("ERC20: insufficient allowance");
    vm.prank (kiloChi);
    del.registerFor ("p", "xx", alice, sgn);

    vm.assertTrue (acc.exists ("p", "x"));
    vm.assertFalse (acc.exists ("p", "xx"));
  }

  function test_registerForSignatureAndOwner () public
  {
    bytes memory sgn = permitSignature (aliceKey);
    vm.prank (kiloChi);
    del.registerFor ("p", "x", alice, sgn);

    vm.expectRevert ("signature did not match owner");
    vm.prank (kiloChi);
    del.registerFor ("p", "y", bob, sgn);

    vm.assertTrue (acc.exists ("p", "x"));
    vm.assertFalse (acc.exists ("p", "y"));
  }

  function test_takeOverName () public
  {
    bytes memory sgn = permitSignature (aliceKey);
    vm.prank (kiloChi);
    del.registerFor ("p", "domob", alice, sgn);

    vm.expectRevert ("only the owner can request a take over");
    vm.prank (kiloChi);
    del.takeOverName ("p", "domob");

    fwd.exec (address (del),
              abi.encodeCall (del.takeOverName, ("p", "domob")),
              alice);

    /* Alice should still have top-level access, which she can now refine
       as desired with meta transactions.  */
    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "grant(string,string,string[],address,uint256,bool)",
            "p", "domob", stringArray ("sub"), alice, 100, false),
        alice);
    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "revoke(string,string,string[],address,bool)",
            "p", "domob", stringArray (), alice, false),
        alice);

    vm.prank (alice);
    del.grant ("p", "domob", stringArray ("sub"), alice, 100, false);

    uint256 tokenId = acc.tokenIdForName ("p", "domob");
    vm.assertEq (acc.ownerOf (tokenId), address (del));
    vm.assertTrue (del.hasAccess ("p", "domob", stringArray ("sub", "foo"),
                                  alice, 100));
    vm.assertFalse (del.hasAccess ("p", "domob", stringArray ("sub", "foo"),
                                   alice, 101));
    vm.assertFalse (del.hasAccess ("p", "domob", stringArray ("other"),
                                   alice, 1));
  }

  /* ************************************************************************ */

  function test_accessPermissionsForSendingMoves () public
  {
    uint256 start = block.timestamp;

    bytes memory sgn = permitSignature (aliceKey);
    vm.prank (kiloChi);
    del.registerFor ("p", "x", alice, sgn);
    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "grant(string,string,string[],address,uint256,bool)",
            "p", "x", stringArray ("sub"), kiloChi, start + 100, false),
        alice);

    vm.warp (start + 50);
    vm.expectRevert ("the message sender has no permission to send moves");
    vm.prank (kiloChi);
    del.sendHierarchicalMove ("p", "x", stringArray ("other"), "{}");

    vm.prank (kiloChi);
    del.sendHierarchicalMove ("p", "x", stringArray ("sub"), "{}");

    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "sendHierarchicalMove(string,string,string[],string)",
            "p", "x", stringArray ("sub"), "{}"),
        kiloChi);

    vm.warp (start + 150);
    vm.expectRevert ("the message sender has no permission to send moves");
    vm.prank (kiloChi);
    del.sendHierarchicalMove ("p", "x", stringArray ("sub"), "{}");

    /* Two moves have been sent successfully, with
        {"sub":{}}
       each, costing 10 units in fees per move.  */
    vm.assertEq (wchi.balanceOf (kiloChi), 1000 - 20);
  }

  function test_wchiPaymentForMoves () public
  {
    bytes memory sgn = permitSignature (aliceKey);
    vm.prank (kiloChi);
    del.registerFor ("p", "x", alice, sgn);
    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "grant(string,string,string[],address,uint256,bool)",
            "p", "x", stringArray (), kiloChi, type (uint256).max, false),
        alice);

    vm.prank (kiloChi);
    del.sendHierarchicalMove (
        "p", "x", stringArray (), "{}", type (uint256).max, 42, alice);
    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "sendHierarchicalMove(string,string,string[],"
                                 "string,uint256,uint256,address)",
            "p", "x", stringArray (), "{}", type (uint256).max, 42, alice),
        kiloChi);
    vm.assertEq (wchi.balanceOf (kiloChi), 1000 - 2 * (2 + 42));
    vm.assertEq (wchi.balanceOf (alice), 2 * 42);

    vm.prank (kiloChi);
    wchi.approve (address (del), 0);
    vm.expectRevert ("ERC20: insufficient allowance");
    vm.prank (kiloChi);
    del.sendHierarchicalMove (
        "p", "x", stringArray (), "{}", type (uint256).max, 42, owner);
    vm.expectRevert ();
    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "sendHierarchicalMove(string,string,string[],"
                                 "string,uint256,uint256,address)",
            "p", "x", stringArray (), "{}", type (uint256).max, 42, owner),
        kiloChi);
  }

  function test_sendsCorrectMove () public
  {
    bytes memory sgn = permitSignature (aliceKey);
    vm.prank (kiloChi);
    del.registerFor ("p", "x", alice, sgn);
    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "grant(string,string,string[],address,uint256,bool)",
            "p", "x", stringArray ("sub"), kiloChi, type (uint256).max, false),
        alice);

    /* This is a JSON injection attempt and should revert.  The exact error
       is not easy to check with expectRevert() due to the meta transaction
       layer in between.  */
    vm.expectRevert ();
    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "sendHierarchicalMove(string,string,string[],string)",
            "p", "x", stringArray ("sub"), "null},{\"other\":{\"foo\":42"),
        kiloChi);

    uint256 tokenId = acc.tokenIdForName ("p", "x");
    vm.expectEmit (address (acc));
    emit IXayaAccounts.Move ("p", "x", "{\"sub\":{\"foo\":42}}",
                             tokenId, acc.nextNonce (tokenId),
                             address (del), 0, address (0));
    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "sendHierarchicalMove(string,string,string[],string)",
            "p", "x", stringArray ("sub"), "{\"foo\":42}"),
        kiloChi);
  }

  /* ************************************************************************ */

  function test_permissionExists () public
  {
    uint256 start = block.timestamp;

    bytes memory sgn = permitSignature (aliceKey);
    vm.prank (kiloChi);
    del.registerFor ("p", "x", alice, sgn);
    uint256 tokenId = acc.tokenIdForName ("p", "x");
    vm.assertEq (acc.ownerOf (tokenId), alice);

    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "grant(string,string,string[],address,uint256,bool)",
            "p", "x", stringArray ("foo"), bob, start + 100, false),
        alice);
    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "grant(string,string,string[],address,uint256,bool)",
            "p", "x", stringArray ("foo", "bar"), bob, start + 10, false),
        bob);

    vm.assertTrue (del.hasAccess ("p", "x", stringArray ("foo", "baz"),
                                  bob, start + 50));

    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "revoke(string,string,string[],address,bool)",
            "p", "x", stringArray ("foo"), bob, false),
        alice);

    vm.assertFalse (del.hasAccess ("p", "x", stringArray ("foo", "baz"),
                                   bob, start + 50));
    vm.assertTrue (del.hasAccess ("p", "x", stringArray ("foo", "bar"),
                                  bob, start + 5));

    vm.warp (start + 5);
    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "expireTree(string,string,string[])",
            "p", "x", stringArray ()),
        kiloChi);
    vm.assertTrue (del.permissionExists (
        tokenId, alice, stringArray ("foo", "bar"), bob, false));

    vm.warp (start + 15);
    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "expireTree(string,string,string[])",
            "p", "x", stringArray ()),
        kiloChi);
    vm.assertFalse (del.permissionExists (tokenId, alice, stringArray ()));

    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "grant(string,string,string[],address,uint256,bool)",
            "p", "x", stringArray ("foo"), bob, type (uint256).max, true),
        alice);
    vm.assertTrue (del.permissionExists (tokenId, alice, stringArray ()));
    fwd.exec (
        address (del),
        abi.encodeWithSignature (
            "resetTree(string,string,string[])",
            "p", "x", stringArray ()),
        alice);
    vm.assertFalse (del.permissionExists (tokenId, alice, stringArray ()));
  }

  /* ************************************************************************ */

}
