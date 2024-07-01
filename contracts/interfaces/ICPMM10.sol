// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface ICPMM10 {
    function token0() external view returns(address);
    function token1() external view returns(address);
}
