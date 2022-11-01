// SPDX-License-Identifier: MIT
// Copyright (C) 2022 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

import "./JsonSubObject.sol";
import "./NamePermissions.sol";

import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@xaya/eth-account-registry/contracts/IXayaAccounts.sol";

/**
 * @dev The main delegation contract.  It uses the permissions tree system
 * implemented in the super contracts, and links it to the actual XayaAccounts
 * contract for sending moves.  It also enables ERC2771 meta transactions.
 */
contract XayaDelegation is NamePermissions, ERC2771Context, IERC721Receiver
{

  /* ************************************************************************ */

  /** @dev The XayaAccounts contract used.  */
  IXayaAccounts public immutable accounts;

  /** @dev The WCHI token used.  */
  IERC20 public immutable wchi;

  /**
   * @dev Temporarily set to true while we expect to receive name NFTs
   * (e.g. while registering for a user).
   *
   * It allows to receive name ERC721 tokens when set.
   */
  bool private allowNameReceive;

  /**
   * @dev Constructs the contract, fixing the XayaAccounts as well as forwarder
   * contracts.
   */
  constructor (IXayaAccounts acc, address fwd)
    ERC2771Context(fwd)
  {
    accounts = acc;
    wchi = accounts.wchiToken ();
    wchi.approve (address (accounts), type (uint256).max);
  }

  /**
   * @dev We accept ERC-721 token transfers only when explicitly specified
   * that we expect one, and we only accept Xaya names at all.
   */
  function onERC721Received (address, address, uint256, bytes calldata)
      public view override returns (bytes4)
  {
    require (msg.sender == address (accounts),
             "only Xaya names can be received");
    require (allowNameReceive, "tokens cannot be received at the moment");
    return IERC721Receiver.onERC721Received.selector;
  }

  /* ************************************************************************ */

  /**
   * @dev Registers a name for a given owner.  This registers the name,
   * transfers it, and then sets operator permissions for the delegation
   * contract with the owner's prepared signature.  With this method, we
   * can enable gas-free name registration with this contract's support
   * for meta transactions.  Returns the new token's ID.
   *
   * The WCHI for the name registration is paid for by _msgSender.
   */
  function registerFor (string memory ns, string memory name,
                        address owner, bytes memory signature)
      public returns (uint256 tokenId)
  {
    uint256 fee = accounts.policy ().checkRegistration (ns, name);
    if (fee > 0)
      require (wchi.transferFrom (_msgSender (), address (this), fee),
               "failed to obtain WCHI from sender");

    allowNameReceive = true;
    tokenId = accounts.register (ns, name);
    allowNameReceive = false;
    accounts.safeTransferFrom (address (this), owner, tokenId);

    /* In theory, we could eliminate the "owner" argument and just recover
       it from the signature always.  But that runs the risk of sending names
       to an unspendable address if the user messes up the signature, so we
       are explicit here to ensure this can't happen as easily.  */
    address fromSig = accounts.permitOperator (address (this), signature);
    require (owner == fromSig, "signature did not match owner");
  }

  /**
   * @dev Takes over a name:  This transfers the name to be owned by
   * the delegation contract (which is irreversible and corresponds to
   * a provable "lock" of the name).  This can only be done by the owner
   * of the name.  The previous owner will be granted top-level permissions,
   * based on which they can then selectively restrict their access if desired.
   */
  function takeOverName (string memory ns, string memory name)
      public
  {
    (uint256 tokenId, address owner) = idAndOwner (ns, name);
    require (_msgSender () == owner, "only the owner can request a take over");

    allowNameReceive = true;
    accounts.safeTransferFrom (owner, address (this), tokenId);
    allowNameReceive = false;

    string[] memory emptyPath;
    /* We need to do a real, external transaction here (rather than an
       internal call), so that the sender is actually the contract now,
       which is the owner and allowed to grant permissions.  */
    this.grant (tokenId, address (this), emptyPath,
                owner, type (uint256).max, false);
  }

  /**
   * @dev Sends a move for the given name that contains some JSON data at
   * the given path.  Verifies that the _msgSender is allowed to send
   * a move for that name and path at the current time.  The nonce used is
   * returned (as from XayaAccounts.move).
   *
   * Any WCHI required for the move will be paid for by _msgSender.
   */
  function sendHierarchicalMove (string memory ns, string memory name,
                                 string[] memory path, string memory mv)
      public returns (uint256)
  {
    return sendHierarchicalMove (ns, name, path, mv, type (uint256).max,
                                 0, address (0));
  }

  /**
   * @dev Sends a move for the given name as the other sendHierarchicalMove
   * method, but allows control over nonce and WCHI payments.
   */
  function sendHierarchicalMove (string memory ns, string memory name,
                                 string[] memory path, string memory mv,
                                 uint256 nonce,
                                 uint256 amount, address receiver)
      public returns (uint256)
  {
    require (hasAccess (ns, name, path, _msgSender (), block.timestamp),
             "the message sender has no permission to send moves");

    string memory fullMove = JsonSubObject.atPath (path, mv);
    uint256 cost = accounts.policy ().checkMove (ns, fullMove) + amount;
    if (cost > 0)
      require (wchi.transferFrom (_msgSender (), address (this), cost),
               "failed to obtain WCHI from sender");

    return accounts.move (ns, name, fullMove, nonce, amount, receiver);
  }

  /* ************************************************************************ */

  /**
   * @dev Computes the tokenId and looks up the current owner for a given name.
   */
  function idAndOwner (string memory ns, string memory name)
      private view returns (uint256 tokenId, address owner)
  {
    tokenId = accounts.tokenIdForName (ns, name);
    owner = accounts.ownerOf (tokenId);
  }

  /* Expose the methods for managing permissions from NamePermissions on a
     per-name basis, with automatic lookup of the tokenId and current owner.

     This is just for convenience.  All logic (and checks!) are done in the
     according methods in NamePermissions, and those could be called directly
     as well by anyone if needed.  */

  function hasAccess (string memory ns, string memory name,
                      string[] memory path,
                      address operator, uint256 atTime)
      public view returns (bool)
  {
    (uint256 tokenId, address owner) = idAndOwner (ns, name);
    return hasAccess (tokenId, owner, path, operator, atTime);
  }

  function grant (string memory ns, string memory name, string[] memory path,
                  address operator, uint256 expiration, bool fallbackOnly)
      public
  {
    (uint256 tokenId, address owner) = idAndOwner (ns, name);
    grant (tokenId, owner, path, operator, expiration, fallbackOnly);
  }

  function revoke (string memory ns, string memory name, string[] memory path,
                   address operator, bool fallbackOnly)
      public
  {
    (uint256 tokenId, address owner) = idAndOwner (ns, name);
    revoke (tokenId, owner, path, operator, fallbackOnly);
  }

  function resetTree (string memory ns, string memory name,
                      string[] memory path)
      public
  {
    (uint256 tokenId, address owner) = idAndOwner (ns, name);
    resetTree (tokenId, owner, path);
  }

  function expireTree (string memory ns, string memory name,
                       string[] memory path)
      public
  {
    (uint256 tokenId, address owner) = idAndOwner (ns, name);
    expireTree (tokenId, owner, path);
  }

  /* ************************************************************************ */

  /* Explicitly specify that we want to use the ERC2771 variants for
     _msgSender and _msgData.  */

  function _msgSender ()
      internal view override(Context, ERC2771Context) returns (address)
  {
    return ERC2771Context._msgSender ();
  }

  function _msgData ()
      internal view override(Context, ERC2771Context) returns (bytes calldata)
  {
    return ERC2771Context._msgData ();
  }

  /* ************************************************************************ */

}
