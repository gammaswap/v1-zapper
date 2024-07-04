// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@gammaswap/v1-core/contracts/libraries/AddressCalculator.sol";
import "@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol";
import "@gammaswap/v1-implementations/contracts/interfaces/math/ICPMMMath.sol";
import "@gammaswap/v1-implementations/contracts/interfaces/external/cpmm/ICPMM.sol";
import "@gammaswap/v1-periphery/contracts/base/Transfers.sol";
import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapFactory.sol";
import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapRouter02.sol";
import "@gammaswap/univ3-rebalancer/contracts/interfaces/ISwapRouter.sol";
import "@gammaswap/univ3-rebalancer/contracts/libraries/Path.sol";
import "@gammaswap/univ3-rebalancer/contracts/libraries/BytesLib.sol";

/// @title BaseZapper contract for all Zapper implementations
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @dev Base contract with common functions used by zapper implementations
abstract contract BaseZapper is Transfers {

    using Path for bytes;
    using BytesLib for bytes;

    /// @dev GammaPool factory contract
    address public immutable factory;

    /// @dev DeltaSwap factory contract
    address public immutable dsFactory;

    /// @dev Math library contract for GammaSwap's token rebalancing calculations
    address public immutable mathLib;

    /// @dev UniswapV2 CFMM router
    address public immutable uniV2Router;

    /// @dev Sushiswap CFMM router
    address public immutable sushiRouter;

    /// @dev DeltaSwap CFMM router
    address public immutable dsRouter;

    /// @dev UniswapV3 CFMM router
    address public immutable uniV3Router;

    /// @dev Initializes the contract by setting `WETH`, `factory`, `dsFactory`, `mathLib`, `uniV2Router`, `sushiRouter`, `dsRouter`, and `uniV3Router`.
    constructor(address _WETH, address _factory, address _dsFactory, address _mathLib, address _uniV2Router, address _sushiRouter, address _dsRouter, address _uniV3Router) Transfers(_WETH){
        factory = _factory;
        dsFactory = _dsFactory;
        mathLib = _mathLib;
        uniV2Router = _uniV2Router;
        sushiRouter = _sushiRouter;
        dsRouter = _dsRouter;
        uniV3Router = _uniV3Router;
    }

    /// @dev See {ITransfers-getGammaPoolAddress}.
    function getGammaPoolAddress(address cfmm, uint16 protocolId) internal virtual override view returns(address) {
        return AddressCalculator.calcAddress(factory, protocolId, AddressCalculator.getGammaPoolKey(cfmm, protocolId));
    }

    /// @dev function to swap tokenIn through path using UniswapV3. Always sells amountIn of tokenIn
    /// @param tokenIn - address of token being swapped
    /// @param amountIn - amount of tokenIn being swapped
    /// @param amountOutMin - expected amount to get from swap with UniswapV3 (slippage control)
    /// @param path - path of UniswapV3 pools to follow to perform swap
    /// @param to - address receiving tokens from sale of tokenIn
    function _uniV3Swap(address tokenIn, uint256 amountIn, uint256 amountOutMin, bytes memory path, address to) internal {
        (address _tokenIn,,) = path.decodeFirstPool();
        require(tokenIn == _tokenIn, "LP_ZAPPER: INVALID_UNIV3_PATH");
        require(uniV3Router != address(0), "LP_ZAPPER: UNIV3_ROUTER_NOT_FOUND");

        // fund router
        GammaSwapLibrary.safeTransfer(tokenIn, uniV3Router, amountIn);

        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: to,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin // minimum of receiving token
        });

        // Executes the swap.
        ISwapRouter(uniV3Router).exactInput(params);
    }

    /// @dev function to swap tokenIn through path using an UniswapV2 style CFMM. Always sells amountIn of tokenIn
    /// @param tokenIn - address of token being swapped
    /// @param amountIn - amount of tokenIn being swapped
    /// @param amountOutMin - expected amount to get from swap with UniswapV3 (slippage control)
    /// @param path - path of tokens to follow to perform swap using CFMM of protocolId
    /// @param to - address receiving tokens from sale of tokenIn
    function _swap(address tokenIn, uint256 amountIn, uint256 amountOutMin, address[] memory path, uint256 protocolId, address to) internal {
        require(tokenIn == path[0] && tokenIn != path[path.length - 1], "LP_ZAPPER: INVALID_PATH");
        require(protocolId > 0, "LP_ZAPPER: INVALID_PROTOCOL");

        address router;
        if(protocolId == 1) {
            require(uniV2Router != address(0), "LP_ZAPPER: UNIV2_ROUTER_NOT_FOUND");
            router = uniV2Router;
        } else if(protocolId == 2) {
            require(sushiRouter != address(0), "LP_ZAPPER: SUSHI_ROUTER_NOT_FOUND");
            router == sushiRouter;
        } else if(protocolId == 3) {
            require(dsRouter != address(0), "LP_ZAPPER: SUSHI_ROUTER_NOT_FOUND");
            router == dsRouter;
        }

        require(router != address(0), "LP_ZAPPER: PROTOCOL_NOT_FOUND");

        GammaSwapLibrary.safeApprove(tokenIn, router, amountIn);

        IDeltaSwapRouter02(router).swapExactTokensForTokens(amountIn, amountOutMin, path, to, block.timestamp); // the last amounts is what was obtained
    }

    /// @dev Calculate token amount of token1 that will be sold from purchasing token0 amount. Therefore always buying token0
    /// @param fee1 - numerator of CFMM fee calculation (e.g. fee1/fee2 = 997/1000 => 30 bps)
    /// @param fee2 - denominator of CFMM fee calculation (e.g. fee1/fee2 = 997/1000 => 30 bps)
    /// @param amount - amount purchasing from CFMM
    /// @param reserve0 - reserves of token0 in CFMM
    /// @param reserve1 - reserves of token1 in CFMM
    /// @return quantity of token1 that has to be sold to purchase 'amount' of token0
    function _calcSoldToken(uint256 fee1, uint256 fee2, uint256 amount, uint256 reserve0, uint256 reserve1) internal virtual view returns(uint256) {
        return reserve1 * amount * fee2 / ((reserve0 - amount) * fee1) + 1;
    }

    /// @dev Calculate quantities to swap to make the ratio of tokensHeld[] match reserves[] post swap
    /// @param fee1 - numerator of CFMM fee calculation (e.g. fee1/fee2 = 997/1000 => 30 bps)
    /// @param fee2 - denominator of CFMM fee calculation (e.g. fee1/fee2 = 997/1000 => 30 bps)
    /// @param tokensHeld - quantities to rebalance through a swap with the CFMM
    /// @param reserves - reserve quantities of CFMM
    /// @param decimals0 - decimals of token0
    /// @param decimals1 - decimals of token1
    /// @return deltas - array with amounts to buy of token0 or token1 to rebalance tokensHeld[] so its ratio matches the ratio of reserves[]
    function _calcDeltasForMaxLP(uint256 fee1, uint256 fee2, uint128[] memory tokensHeld, uint128[] memory reserves, uint8 decimals0, uint8 decimals1) internal virtual view returns(int256[] memory deltas) {
        // we only buy, therefore when desiredRatio > loanRatio, invert reserves, collaterals, and desiredRatio
        deltas = new int256[](2);

        uint256 leftVal = uint256(reserves[0]) * uint256(tokensHeld[1]);
        uint256 rightVal = uint256(reserves[1]) * uint256(tokensHeld[0]);

        if(leftVal > rightVal) {
            deltas = ICPMMMath(mathLib).calcDeltasForMaxLP(tokensHeld[0], tokensHeld[1], reserves[0], reserves[1], fee1, fee2, decimals0);
            (deltas[0], deltas[1]) = (deltas[1], 0); // swap result, 1st root (index 0) is the only feasible trade
        } else if(leftVal < rightVal) {
            deltas = ICPMMMath(mathLib).calcDeltasForMaxLP(tokensHeld[1], tokensHeld[0], reserves[1], reserves[0], fee1, fee2, decimals1);
            (deltas[0], deltas[1]) = (0, deltas[1]); // swap result, 1st root (index 0) is the only feasible trade
        }
    }

    /// @dev Get last token from UniswapV3 path
    /// @param path - UniswapV3 swap path
    /// @return tokenOut - last token in path
    function _getTokenOut(bytes memory path) internal view returns(address tokenOut) {
        bytes memory _path = path.skipToken();
        while (_path.hasMultiplePools()) {
            _path = _path.skipToken();
        }
        tokenOut = _path.toAddress(0);
    }

    /// @dev Swap fundAmount of tokenIn using CFMM or UniswapV3
    /// @dev Used when zapping in and the tokenIn does not match one of the tokens (token0 or token1) of the GammaPool
    /// @dev If uniV3Path is not set, we use path parameter with protocolId.
    /// @dev last token to obtain from path or uniV3Path must be either token0 or token1
    /// @param token0 - token0 of GammaPool
    /// @param token1 - token1 of GammaPool
    /// @param tokenIn - token being swapped into token0 or token1
    /// @param fundAmount - amount of tokenIn being swapped
    /// @param minAmount - minimum amount expected to be received from swap to control for slippage
    /// @param protocolId - protocolId of CFMM used to swap, when using the path parameter
    /// @param path - path to follow to swap tokenIn into token0 or token1 using the CFMM of protocolId
    /// @param uniV3Path - UniswapV3 path to follow to swap tokenIn into token0 or token1. When set, ignore path parameter and protocolId parameters
    /// @return tokenOut - token that tokenIn was swapped into
    /// @return balanceOut - amount of tokenOut received from swapping tokenIn
    function _swapTokenInFull(address token0, address token1, address tokenIn, uint256 fundAmount, uint256 minAmount, uint16 protocolId, address[] memory path, bytes memory uniV3Path) internal virtual returns(address tokenOut, uint256 balanceOut) {
        require(fundAmount > 1000, "LP_ZAPPER: INVALID_FUND_AMOUNT");
        require((protocolId > 0 && path.length > 1) || uniV3Path.length > 1, "LP_ZAPPER: NO_FUND_SWAP_PATH");

        if(uniV3Path.length > 0) {
            tokenOut = _getTokenOut(uniV3Path);
            require(token0 == tokenOut || token1 == tokenOut, "LP_ZAPPER: INVALID_TOKEN_OUT");
            _uniV3Swap(tokenIn, fundAmount, minAmount, uniV3Path, address(this));
        } else {
            tokenOut = path[path.length - 1];
            require(token0 == tokenOut || token1 == tokenOut, "LP_ZAPPER: INVALID_TOKEN_OUT");
            _swap(tokenIn, fundAmount, minAmount, path, protocolId, address(this));
        }
        balanceOut = GammaSwapLibrary.balanceOf(tokenOut, address(this));
    }

    /// @dev Calculate amount to sell of tokenIn to convert tokenIn into the matching ratio of token0 and token1 of the CFMM
    /// @dev This function assumes tokenIn is either token0 or token1
    /// @param cfmm - address of CFMM of token0 and token1
    /// @param protocolId - protocolId of CFMM. Only used to get the correct trading fee when CFMM is DeltaSwap
    /// @param token0 - token0 of GammaPool
    /// @param token1 - token1 of GammaPool
    /// @param tokenIn - token being swapped into token0 or token1
    /// @param fundAmount - amount of tokenIn being swapped
    /// @return sellAmount - amount to sell of tokenIn to convert tokenIn into the same ratio of the CFMM tokens post swap
    function _calcSellAmount(address cfmm, uint16 protocolId, address token0, address token1, address tokenIn, uint256 fundAmount) internal view returns(uint256 sellAmount) {
        uint256 fee1 = 997;
        uint256 fee2 = 1000;
        if(protocolId == 3) {
            fee1 = 1000 - IDeltaSwapFactory(dsFactory).dsFee();
        }
        uint128[] memory reserves = new uint128[](2);
        (reserves[0], reserves[1],) = ICPMM(cfmm).getReserves();
        uint128[] memory tokensHeld = new uint128[](2);
        if(tokenIn == token0) {
            tokensHeld[0] = uint128(fundAmount);
            tokensHeld[1] = 1;
            int256[] memory deltas = _calcDeltasForMaxLP(fee1, fee2, tokensHeld, reserves, GammaSwapLibrary.decimals(token0), GammaSwapLibrary.decimals(token1));
            sellAmount = _calcSoldToken(fee1, fee2, uint256(deltas[1]), reserves[1], reserves[0]);
        } else {
            tokensHeld[0] = 1;
            tokensHeld[1] = uint128(fundAmount);
            int256[] memory deltas = _calcDeltasForMaxLP(fee1, fee2, tokensHeld, reserves, GammaSwapLibrary.decimals(token0), GammaSwapLibrary.decimals(token1));
            sellAmount = _calcSoldToken(fee1, fee2, uint256(deltas[0]), reserves[0], reserves[1]);
        }
    }
}
