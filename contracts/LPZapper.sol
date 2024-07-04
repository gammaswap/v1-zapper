// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/ILPZapper.sol";
import "./BaseZapper.sol";

contract LPZapper is ILPZapper, BaseZapper {

    address public immutable positionManager;

    constructor(address _WETH, address _factory, address _dsFactory, address _positionManager, address _mathLib, address _uniV2Router, address _sushiRouter, address _dsRouter, address _uniV3Router)
        BaseZapper(_WETH, _factory, _dsFactory, _mathLib, _uniV2Router, _sushiRouter, _dsRouter, _uniV3Router) {
        positionManager = _positionManager;
    }

    function zapInETH(IPositionManager.DepositReservesParams memory params, LPSwapParams memory lpSwap, FundSwapParams memory fundSwap) external override virtual payable {
        require(msg.value > 0, "LP_ZAPPER: ZERO_ETH");

        uint256 fundAmount = msg.value;

        IWETH(WETH).deposit{value: fundAmount}(); // wrap only what is needed

        zapIn(WETH, fundAmount, params, lpSwap, fundSwap);
    }

    function zapInToken(address tokenIn, uint256 fundAmount, IPositionManager.DepositReservesParams memory params, LPSwapParams memory lpSwap, FundSwapParams memory fundSwap) external override virtual {
        require(fundAmount > 1000, "LP_ZAPPER: INVALID_FUND_AMOUNT");
        require(tokenIn != address(0), "LP_ZAPPER: ZERO_ADDRESS");

        GammaSwapLibrary.safeTransferFrom(tokenIn, msg.sender, address(this), fundAmount);

        zapIn(tokenIn, fundAmount, params, lpSwap, fundSwap);
    }

    function zapIn(address tokenIn, uint256 fundAmount, IPositionManager.DepositReservesParams memory params, LPSwapParams memory lpSwap, FundSwapParams memory fundSwap) internal virtual {
        require(params.to != address(0), "LP_ZAPPER: INVALID_PARAM_TO");
        require(params.cfmm != address(0), "LP_ZAPPER: INVALID_PARAM_CFMM");

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
                lpSwap.amount = calcSellAmount(params.cfmm, params.protocolId, token0, token1, tokenIn, fundAmount);
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

    function zapOutETH(IPositionManager.WithdrawReservesParams memory params, LPSwapParams memory lpSwap0, LPSwapParams memory lpSwap1) external override virtual {
        require(params.to != address(0), "LP_ZAPPER: INVALID_PARAM_TO");

        if(ICPMM(params.cfmm).token0() == WETH) {
            require((lpSwap1.path.length > 0 && lpSwap1.path[lpSwap1.path.length - 1] == WETH) || (lpSwap1.uniV3Path.length > 0 && getTokenOut(lpSwap1.uniV3Path) == WETH),"LP_ZAPPER: PATH1_EXIT_NOT_WETH");
        } else if(ICPMM(params.cfmm).token1() == WETH) {
            require((lpSwap0.path.length > 0 && lpSwap0.path[lpSwap0.path.length - 1] == WETH) || (lpSwap0.uniV3Path.length > 0 && getTokenOut(lpSwap0.uniV3Path) == WETH),"LP_ZAPPER: PATH0_EXIT_NOT_WETH");
        } else {
            require((lpSwap0.path.length > 0 && lpSwap0.path[lpSwap0.path.length - 1] == WETH) || (lpSwap0.uniV3Path.length > 0 && getTokenOut(lpSwap0.uniV3Path) == WETH),"LP_ZAPPER: PATH0_EXIT_NOT_WETH");
            require((lpSwap1.path.length > 0 && lpSwap1.path[lpSwap1.path.length - 1] == WETH) || (lpSwap1.uniV3Path.length > 0 && getTokenOut(lpSwap1.uniV3Path) == WETH),"LP_ZAPPER: PATH1_EXIT_NOT_WETH");
        }

        address to = params.to;
        params.to = address(this);

        zapOutToken(params, lpSwap0, lpSwap1);

        unwrapWETH(0, to);
    }

    function zapOutToken(IPositionManager.WithdrawReservesParams memory params, LPSwapParams memory lpSwap0, LPSwapParams memory lpSwap1) public override virtual {
        require(params.to != address(0), "LP_ZAPPER: INVALID_PARAM_TO");
        require(params.cfmm != address(0), "LP_ZAPPER: INVALID_PARAM_CFMM");
        address to = params.to;
        params.to = address(this);

        address gammaPool = getGammaPoolAddress(params.cfmm, params.protocolId);

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
}
