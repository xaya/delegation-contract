
// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

import "@xaya/eth-account-registry/src/IXayaAccounts.sol";

/**
 * @dev Helper library defining constants such as token addresses
 * used for deployments on the Polygon network.
 */
library PolygonConfig
{

  /** @dev Xaya accounts contract.  */
  IXayaAccounts public constant acc
      = IXayaAccounts (0x8C12253F71091b9582908C8a44F78870Ec6F304F);

  /** @dev ERC-2771 forwarder contract to use for meta transactions.  */
  address public constant fwd = 0xf0511f123164602042ab2bCF02111fA5D3Fe97CD;

}
