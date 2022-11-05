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

## Deployment

**Note:** The contract is still in testing phase, and the deployments
here must not be considered final.  The contract may be insecure, and
should just be used for testing!

| Network | Address |
| ------- | ------- |
| Polygon | [0xEB4c2EF7874628B646B8A59e4A309B94e14C2a6B](https://polygonscan.com/address/0xeb4c2ef7874628b646b8a59e4a309b94e14c2a6b) |
| Mumbai | [0xD5fd31CfD529498B1668fE9dFa336c475AC57C76](https://mumbai.polygonscan.com/address/0xd5fd31cfd529498b1668fe9dfa336c475ac57c76) |
