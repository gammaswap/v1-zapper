// SPDX-License-Identifier: UNLICENSED
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

abstract contract BaseZapper is Transfers {

    using Path for bytes;
    using BytesLib for bytes;

    address public immutable factory;
    address public immutable dsFactory;
    address public immutable mathLib;
    address public immutable uniV2Router;
    address public immutable sushiRouter;
    address public immutable dsRouter;
    address public immutable uniV3Router;

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

    function _swap(address tokenIn, uint256 amountIn, uint256 amountOutMin, address[] memory path, uint256 protocolId, address to) internal {
        require(tokenIn == path[0], "LP_ZAPPER: INVALID_PATH");

        address router = dsRouter;
        if(protocolId == 1) {
            require(uniV2Router != address(0), "LP_ZAPPER: UNIV2_ROUTER_NOT_FOUND");
            router = uniV2Router;
        } else if(protocolId == 2) {
            require(sushiRouter != address(0), "LP_ZAPPER: SUSHI_ROUTER_NOT_FOUND");
            router == sushiRouter;
        }

        GammaSwapLibrary.safeApprove(tokenIn, router, amountIn);

        IDeltaSwapRouter02(router).swapExactTokensForTokens(amountIn, amountOutMin, path, to, block.timestamp); // the last amounts is what was obtained
    }

    // always buying token0
    function _calcSoldToken(uint256 fee1, uint256 fee2, uint256 delta, uint256 reserve0, uint256 reserve1) internal virtual view returns(uint256) {
        return reserve1 * delta * fee2 / ((reserve0 - delta) * fee1) + 1;
    }

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

    function getTokenOut(bytes memory path) internal view returns(address tokenOut) {
        bytes memory _path = path.skipToken();
        while (_path.hasMultiplePools()) {
            _path = _path.skipToken();
        }
        tokenOut = _path.toAddress(0);
    }

    function swapTokenInFull(address token0, address token1, address tokenIn, uint256 fundAmount, uint256 minAmount, uint16 protocolId, address[] memory path, bytes memory uniV3Path) internal virtual returns(address tokenOut, uint256 balanceOut) {
        require(fundAmount > 1000, "LP_ZAPPER: INVALID_FUND_AMOUNT");
        require(path.length > 1 || uniV3Path.length > 1, "LP_ZAPPER: NO_FUND_SWAP_PATH");

        if(uniV3Path.length > 0) {
            tokenOut = getTokenOut(uniV3Path);
            require(token0 == tokenOut || token1 == tokenOut, "LP_ZAPPER: INVALID_TOKEN_OUT");
            _uniV3Swap(tokenIn, fundAmount, minAmount, uniV3Path, address(this));
        } else {
            tokenOut = path[path.length - 1];
            require(token0 == tokenOut || token1 == tokenOut, "LP_ZAPPER: INVALID_TOKEN_OUT");
            _swap(tokenIn, fundAmount, minAmount, path, protocolId, address(this));
        }
        balanceOut = GammaSwapLibrary.balanceOf(tokenOut, address(this));
    }

    function calcSellAmount(address cfmm, uint16 protocolId, address token0, address token1, address tokenIn, uint256 fundAmount) internal view returns(uint256 sellAmount) {
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
