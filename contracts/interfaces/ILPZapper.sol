// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@gammaswap/v1-periphery/contracts/interfaces/IPositionManager.sol";

interface ILPZapper {

    struct FundSwapParams {
        uint16 protocolId;
        address[] path;
        bytes uniV3Path;
    }

    struct LPSwapParams {
        uint256 amount;
        uint16 protocolId;
        address[] path;
        bytes uniV3Path;
    }

    function zapInETH(IPositionManager.DepositReservesParams memory params, LPSwapParams memory lpSwap, FundSwapParams memory fundSwap) external payable;
    function zapOutETH(IPositionManager.WithdrawReservesParams memory params, LPSwapParams memory lpSwap0, LPSwapParams memory lpSwap1) external payable;

    function zapInToken(address tokenIn, uint256 fundAmount, IPositionManager.DepositReservesParams memory params, LPSwapParams memory lpSwap, FundSwapParams memory fundSwap) external;
    function zapOutToken(IPositionManager.WithdrawReservesParams memory params, LPSwapParams memory lpSwap0, LPSwapParams memory lpSwap1) external;
}
