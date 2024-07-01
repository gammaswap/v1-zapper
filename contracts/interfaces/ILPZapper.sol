// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@gammaswap/v1-periphery/contracts/interfaces/IPositionManager.sol";

interface ILPZapper {
    function addLiquidity(address[] memory tokens, uint256[] memory amounts, uint256[] memory amountOutMin, address[] calldata path0, address[] calldata path1, bytes memory uniV3Path0, bytes memory uniV3Path1, IPositionManager.DepositReservesParams memory params) external;

    function removeLiquidity(IPositionManager.WithdrawReservesParams calldata params, uint256[] memory amountOutMin, address[] calldata path0, address[] calldata path1, bytes memory uniV3Path0, bytes memory uniV3Path1) external;
}
