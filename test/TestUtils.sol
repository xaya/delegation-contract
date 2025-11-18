// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

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

function stringArray (string memory a, string memory b, string memory c,
                      string memory d, string memory e)
    pure returns (string[] memory res)
{
  res = new string[] (5);
  res[0] = a;
  res[1] = b;
  res[2] = c;
  res[3] = d;
  res[4] = e;
}

function addressArray () pure returns (address[] memory)
{
  return new address[] (0);
}

function addressArray (address a)
    pure returns (address[] memory res)
{
  res = new address[] (1);
  res[0] = a;
}

function addressArray (address a, address b)
    pure returns (address[] memory res)
{
  res = new address[] (2);
  res[0] = a;
  res[1] = b;
}

function addressArray (address a, address b, address c)
    pure returns (address[] memory res)
{
  res = new address[] (3);
  res[0] = a;
  res[1] = b;
  res[2] = c;
}

function addressArray (address a, address b, address c, address d)
    pure returns (address[] memory res)
{
  res = new address[] (4);
  res[0] = a;
  res[1] = b;
  res[2] = c;
  res[3] = d;
}

function addressArray (address a, address b, address c, address d, address e)
    pure returns (address[] memory res)
{
  res = new address[] (5);
  res[0] = a;
  res[1] = b;
  res[2] = c;
  res[3] = d;
  res[4] = e;
}
