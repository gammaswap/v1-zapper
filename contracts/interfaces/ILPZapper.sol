// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@gammaswap/v1-periphery/contracts/interfaces/IPositionManager.sol";

/// @title Interface for LPZapper contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @dev Interface for contract that zaps in/out liquidity from GammaPools using a single token or ETH
interface ILPZapper {

    /// @dev Instructions to swap zapped in token into one of the tokens of the GammaPool, if zapped in token is not one of the GammaPool's tokens
    struct FundSwapParams {
        /// @dev Used with path parameter to specify protocol of CFMM used to swap token
        uint16 protocolId;
        /// @dev Path to swap token using protocolId's CFMM
        address[] path;
        /// @dev Path to swap token if using UniV3. Does not need protocolId
        bytes uniV3Path;
    }

    /// @dev Instructions to swap one of the GammaPool's tokens into any other token while zapping in or out
    struct LPSwapParams {
        /// @dev When used to zapIn, it determines the quantity of one token to swap into the other token. When used in zapOut, it's used for slippage control with UniV3 or protocolId's CFMM
        uint256 amount;
        /// @dev Used with path parameter to specify protocol of CFMM used to swap token
        uint16 protocolId;
        /// @dev Path to swap token using protocolId's CFMM
        address[] path;
        /// @dev Path to swap token if using UniV3. Does not need protocolId
        bytes uniV3Path;
    }

    /// @dev Zap in ETH into a GammaPool of any token pair specified in the DepositReservesParams
    /// @param params - DepositReservesParams of struct to deposit liquidity into GammaPool
    /// @param lpSwap - instructions to swap half of the zapped in token into the other token of the GammaPool
    /// @param fundSwap - instructions to swap the zapped in token into one of the tokens of the pool if the zapped in token is neither of the GammaPool's tokens
    function zapInETH(IPositionManager.DepositReservesParams memory params, LPSwapParams memory lpSwap, FundSwapParams memory fundSwap) external payable;

    /// @dev Zap out GammaPool tokens specified in the WithdrawReservesParams as ETH
    /// @dev Swap paths to convert tokens into ETH must end in WETH. Therefore, only need to provide a path if a withdrawn token is not already WETH
    /// @param params - WithdrawReservesParams of struct to withdraw liquidity from the GammaPool
    /// @param lpSwap0 - instructions to swap token0 withdrawn from the GammaPool into WETH
    /// @param lpSwap1 - instructions to swap token1 withdrawn from the GammaPool into WETH
    function zapOutETH(IPositionManager.WithdrawReservesParams memory params, LPSwapParams memory lpSwap0, LPSwapParams memory lpSwap1) external;

    /// @dev Zap in any token into a GammaPool of any token pair specified in the DepositReservesParams
    /// @param params - DepositReservesParams of struct to deposit liquidity into GammaPool
    /// @param lpSwap - instructions to swap half of the zapped in token into the other token of the GammaPool
    /// @param fundSwap - instructions to swap the zapped in token into one of the tokens of the pool if the zapped in token is neither of the GammaPool's tokens
    function zapInToken(address tokenIn, uint256 fundAmount, IPositionManager.DepositReservesParams memory params, LPSwapParams memory lpSwap, FundSwapParams memory fundSwap) external;

    /// @dev Zap out GammaPool tokens specified in the WithdrawReservesParams as the destination token specified in the lpSwap0 and lpSwap1 parameters
    /// @param params - WithdrawReservesParams of struct to withdraw liquidity from the GammaPool
    /// @param lpSwap0 - instructions to swap token0 withdrawn from the GammaPool into any token
    /// @param lpSwap1 - instructions to swap token1 withdrawn from the GammaPool into any token
    function zapOutToken(IPositionManager.WithdrawReservesParams memory params, LPSwapParams memory lpSwap0, LPSwapParams memory lpSwap1) external;
}
