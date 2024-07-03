// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol";
import "@gammaswap/v1-core/contracts/libraries/AddressCalculator.sol";
import "@gammaswap/v1-implementations/contracts/interfaces/math/ICPMMMath.sol";
import "@gammaswap/v1-implementations/contracts/interfaces/external/cpmm/ICPMM.sol";
import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapRouter02.sol";
import "@gammaswap/univ3-rebalancer/contracts/interfaces/ISwapRouter.sol";
import "@gammaswap/univ3-rebalancer/contracts/libraries/Path.sol";
import "@gammaswap/univ3-rebalancer/contracts/libraries/BytesLib.sol";

import "./interfaces/ILPZapper.sol";

contract LPZapper is ILPZapper {

    using Path for bytes;
    using BytesLib for bytes;

    address public immutable factory;
    address public immutable positionManager;
    address public immutable mathLib;
    address public immutable uniV2Router;
    address public immutable sushiRouter;
    address public immutable dsRouter;
    address public immutable uniV3Router;

    constructor(address _factory, address _positionManager, address _mathLib, address _uniV2Router, address _sushiRouter, address _dsRouter, address _uniV3Router) {
        factory = _factory;
        positionManager = _positionManager;
        mathLib = _mathLib;
        uniV2Router = _uniV2Router;
        sushiRouter = _sushiRouter;
        dsRouter = _dsRouter;
        uniV3Router = _uniV3Router;
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

    function calcSellAmount(address cfmm, address token0, address token1, address tokenIn, uint256 fundAmount) internal view returns(uint256 sellAmount) {
        uint128[] memory reserves = new uint128[](2);
        (reserves[0], reserves[1],) = ICPMM(cfmm).getReserves();
        uint128[] memory tokensHeld = new uint128[](2);
        if(tokenIn == token0) {
            tokensHeld[0] = uint128(fundAmount);
            tokensHeld[1] = 1;
            int256[] memory deltas = _calcDeltasForMaxLP(tokensHeld, reserves, GammaSwapLibrary.decimals(token0), GammaSwapLibrary.decimals(token1));
            sellAmount = _calcSoldToken(uint256(deltas[1]), reserves[1], reserves[0]);
        } else {
            tokensHeld[0] = 1;
            tokensHeld[1] = uint128(fundAmount);
            int256[] memory deltas = _calcDeltasForMaxLP(tokensHeld, reserves, GammaSwapLibrary.decimals(token0), GammaSwapLibrary.decimals(token1));
            sellAmount = _calcSoldToken(uint256(deltas[0]), reserves[0], reserves[1]);
        }
    }

    function zapIn(address tokenIn, uint256 fundAmount, IPositionManager.DepositReservesParams memory params, LPSwapParams memory lpSwap, FundSwapParams memory fundSwap) external override virtual {
        require(fundAmount > 1000, "LP_ZAPPER: INVALID_FUND_AMOUNT");
        require(tokenIn != address(0), "LP_ZAPPER: ZERO_ADDRESS");

        GammaSwapLibrary.safeTransferFrom(tokenIn, msg.sender, address(this), fundAmount);

        address token0 = ICPMM(params.cfmm).token0();
        address token1 = ICPMM(params.cfmm).token1();

        // convert everything into one of the pool's token if it's not
        if(tokenIn != token0 && tokenIn != token1) {
            (tokenIn, fundAmount) = swapTokenInFull(token0, token1, tokenIn, fundAmount, 0, fundSwap.protocolId, fundSwap.path, fundSwap.uniV3Path);
        }

        require(tokenIn == token0 || tokenIn == token1, "LP_ZAPPER: INVALID_TOKEN_IN");

        address tokenOut = tokenIn == token0 ? token1 : token0;

        if(lpSwap.uniV3Path.length > 0) {
            require(tokenOut == getTokenOut(lpSwap.uniV3Path), "LP_ZAPPER: INVALID_TOKEN_OUT");
            require(lpSwap.amount > 0 && fundAmount > lpSwap.amount, "LP_ZAPPER: INVALID_SELL_AMOUNT");
            _uniV3Swap(tokenIn, lpSwap.amount, 0, lpSwap.uniV3Path, address(this));
        } else {
            if(lpSwap.amount == 0) {
                lpSwap.path = new address[](2);
                lpSwap.path[0] = tokenIn;
                lpSwap.path[1] = tokenOut;
                lpSwap.protocolId = params.protocolId;
                ICPMM(params.cfmm).sync();
                lpSwap.amount = calcSellAmount(params.cfmm, token0, token1, tokenIn, fundAmount);
            }

            require(lpSwap.amount > 0, "LP_ZAPPER: INVALID_SELL_AMOUNT");
            _swap(tokenIn, lpSwap.amount, 0, lpSwap.path, lpSwap.protocolId, address(this));
        }

        params.amountsDesired = new uint256[](2);
        params.amountsDesired[0] = GammaSwapLibrary.balanceOf(token0, address(this));
        params.amountsDesired[1] = GammaSwapLibrary.balanceOf(token1, address(this));
        params.deadline = block.timestamp;

        GammaSwapLibrary.safeApprove(token0, positionManager, params.amountsDesired[0]);
        GammaSwapLibrary.safeApprove(token1, positionManager, params.amountsDesired[1]);

        IPositionManager(positionManager).depositReserves(params); //params must be to send to here

        fundAmount = GammaSwapLibrary.balanceOf(token0, address(this));
        if(fundAmount > 0) GammaSwapLibrary.safeTransfer(token0, params.to, fundAmount);

        fundAmount = GammaSwapLibrary.balanceOf(token1, address(this));
        if(fundAmount > 0) GammaSwapLibrary.safeTransfer(token1, params.to, fundAmount);
    }

    function zapOut(IPositionManager.WithdrawReservesParams memory params, LPSwapParams memory lpSwap0, LPSwapParams memory lpSwap1) external override {
        address to = params.to;
        params.to = address(this);

        address gammaPool = AddressCalculator.calcAddress(factory, params.protocolId, AddressCalculator.getGammaPoolKey(params.cfmm, params.protocolId));

        GammaSwapLibrary.safeTransferFrom(gammaPool, msg.sender, address(this), params.amount);

        GammaSwapLibrary.safeApprove(gammaPool, positionManager, params.amount);
        (uint256[] memory reserves,) = IPositionManager(positionManager).withdrawReserves(params); //params must be to send to here

        address[] memory lpTokens = new address[](2);
        lpTokens[0] = ICPMM(params.cfmm).token0();
        lpTokens[1] = ICPMM(params.cfmm).token1();

        if(lpSwap0.path.length > 0 || lpSwap0.uniV3Path.length > 0) {
            if(lpSwap0.uniV3Path.length > 0) {
                _uniV3Swap(lpTokens[0], reserves[0], lpSwap0.amount, lpSwap0.uniV3Path, to);
            } else {
                _swap(lpTokens[0], reserves[0], lpSwap0.amount, lpSwap0.path, lpSwap0.protocolId, to);
            }
        } else {
            GammaSwapLibrary.safeTransfer(lpTokens[0], to, reserves[0]);
        }
        if(lpSwap1.path.length > 0 || lpSwap1.uniV3Path.length > 0) {
            if(lpSwap1.uniV3Path.length > 0) {
                _uniV3Swap(lpTokens[1], reserves[1], lpSwap1.amount, lpSwap1.uniV3Path, to);
            } else {
                _swap(lpTokens[1], reserves[1], lpSwap1.amount, lpSwap1.path, lpSwap1.protocolId, to);
            }
        } else {
            GammaSwapLibrary.safeTransfer(lpTokens[1], to, reserves[1]);
        }
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
    function _calcSoldToken(uint256 delta, uint256 reserve0, uint256 reserve1) internal virtual view returns(uint256) {
        return reserve1 * delta * 1000 / ((reserve0 - delta) * 997) + 1;
    }

    function _calcDeltasForMaxLP(uint128[] memory tokensHeld, uint128[] memory reserves, uint8 decimals0, uint8 decimals1) internal virtual view returns(int256[] memory deltas) {
        // we only buy, therefore when desiredRatio > loanRatio, invert reserves, collaterals, and desiredRatio
        deltas = new int256[](2);

        uint256 leftVal = uint256(reserves[0]) * uint256(tokensHeld[1]);
        uint256 rightVal = uint256(reserves[1]) * uint256(tokensHeld[0]);

        if(leftVal > rightVal) {
            deltas = _calcDeltasForMaxLPStaticCall(tokensHeld[0], tokensHeld[1], reserves[0], reserves[1], decimals0);
            (deltas[0], deltas[1]) = (deltas[1], 0); // swap result, 1st root (index 0) is the only feasible trade
        } else if(leftVal < rightVal) {
            deltas = _calcDeltasForMaxLPStaticCall(tokensHeld[1], tokensHeld[0], reserves[1], reserves[0], decimals1);
            (deltas[0], deltas[1]) = (0, deltas[1]); // swap result, 1st root (index 0) is the only feasible trade
        }
    }

    function _calcDeltasForMaxLPStaticCall(uint128 tokensHeld0, uint128 tokensHeld1, uint128 reserve0, uint128 reserve1,
        uint8 decimals0) internal virtual view returns(int256[] memory deltas) {

        // TODO: call got get correct fee for IDeltaSwapPair from DeltaSwapFactory
        // always buys
        deltas = ICPMMMath(mathLib).calcDeltasForMaxLP(tokensHeld0, tokensHeld1, reserve0, reserve1, 997, 1000, decimals0);
    }
}
