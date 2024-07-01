// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ICPMM10 {
    function token0() external view returns(address);
    function token1() external view returns(address);
}
