# Xaya Accounts Delegation

The Xaya platform on EVM chains (e.g. Polygon) is based on an
[ERC-721](https://erc721.org/) contract implementing
[Xaya accounts](https://github.com/xaya/polygon-contract).  This contract
is by design very basic and mostly non-upgradable, to ensure
decentralisation and trustlessness of the platform to a maximum.

The contract supports basic "delegation" of the right to make moves on
behalf of some account, though, through ERC-721 approvals.  This repository
contains an extension contract, which is meant to be given approval, and
which then implements more advanced delegation features on top of the
base contract.

It enables [native meta transactions](https://eips.ethereum.org/EIPS/eip-2771)
for sending moves from accounts without gas (improved UX, temporary
addresses), selective delegation of the right to send moves (e.g. restricted
to particular games or even types of moves) and more.

Full details can be found in the
[design doc](https://docs.google.com/document/d/1IDB8GOt1FJt6Tq2E2AkvQFRcvEBJvXRf1KINoK0-sSQ/edit?usp=sharing).
