// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

/* Construct arrays of 0-4 members easily.  */

function stringArray () pure returns (string[] memory)
{
  return new string[] (0);
}

function stringArray (string memory a)
    pure returns (string[] memory res)
{
  res = new string[] (1);
  res[0] = a;
}

function stringArray (string memory a, string memory b)
    pure returns (string[] memory res)
{
  res = new string[] (2);
  res[0] = a;
  res[1] = b;
}

function stringArray (string memory a, string memory b, string memory c)
    pure returns (string[] memory res)
{
  res = new string[] (3);
  res[0] = a;
  res[1] = b;
  res[2] = c;
}

function stringArray (string memory a, string memory b, string memory c,
                      string memory d)
    pure returns (string[] memory res)
{
  res = new string[] (4);
  res[0] = a;
  res[1] = b;
  res[2] = c;
  res[3] = d;
}
