// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol";
import "@gammaswap/univ3-rebalancer/contracts/interfaces/ISwapRouter.sol";
import "@gammaswap/univ3-rebalancer/contracts/libraries/Path.sol";
import "@gammaswap/univ3-rebalancer/contracts/libraries/BytesLib.sol";

import "./interfaces/ICPMM10.sol";
import "./interfaces/IDeltaSwapRouter10.sol";
import "./interfaces/ILPZapper.sol";

contract LPZapper is ILPZapper {

    using Path for bytes;
    using BytesLib for bytes;

    address public immutable factory;
    address public immutable positionManager;
    address public immutable uniV2Router;
    address public immutable sushiRouter;
    address public immutable dsRouter;
    address public immutable uniV3Router;

    constructor(address _factory, address _positionManager, address _uniV2Router, address _sushiRouter, address _dsRouter, address _uniV3Router) {
        factory = _factory;
        positionManager = _positionManager;
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

    function addLiquidity(address[] memory tokens, uint256[] memory amounts, uint256[] memory amountOutMin, address[] calldata path0, address[] calldata path1,
        bytes memory uniV3Path0, bytes memory uniV3Path1, IPositionManager.DepositReservesParams memory params) external override {
        require(tokens.length == 2, "LP_ZAPPER: INVALID_TOKENS_LENGTH");
        require(amounts.length == 2, "LP_ZAPPER: INVALID_AMOUNTS_LENGTH");
        require(amountOutMin.length == 2, "LP_ZAPPER: INVALID_AMOUNTS_OUT_MIN_LENGTH");
        require(params.to != address(this), "LP_ZAPPER: INVALID_DEPOSIT_TO");

        if(tokens[0] != address(0) && amounts[0] > 0) GammaSwapLibrary.safeTransferFrom(tokens[0], msg.sender, address(this), amounts[0]);
        if(tokens[1] != address(0) && amounts[1] > 0) GammaSwapLibrary.safeTransferFrom(tokens[1], msg.sender, address(this), amounts[1]);

        address[] memory lpTokens = new address[](2);
        lpTokens[0] = ICPMM10(params.cfmm).token0();
        lpTokens[1] = ICPMM10(params.cfmm).token1();

        if(path0.length > 0 || uniV3Path0.length > 0) {
            if(uniV3Path0.length > 0) {
                require(lpTokens[0] == getTokenOut(uniV3Path0), "LP_ZAPPER: INVALID_TOKEN0_OUT");
                _uniV3Swap(tokens[0], amounts[0], amountOutMin[0], uniV3Path0, address(this));
            } else {
                require(lpTokens[0] == path0[path0.length - 1], "LP_ZAPPER: INVALID_TOKEN0_OUT");
                _swap(tokens[0], amounts[0], amountOutMin[0], path0, params.protocolId, address(this));
            }
        }

        if(path1.length > 0 || uniV3Path1.length > 0) {
            if(uniV3Path1.length > 0) {
                require(lpTokens[1] == getTokenOut(uniV3Path1), "LP_ZAPPER: INVALID_TOKEN1_OUT");
                _uniV3Swap(tokens[1], amounts[1], amountOutMin[1], uniV3Path1, address(this));
            } else {
                require(lpTokens[1] == path1[path1.length - 1], "LP_ZAPPER: INVALID_TOKEN0_OUT");
                _swap(tokens[1], amounts[1], amountOutMin[1], path1, params.protocolId, address(this));
            }
        }

        IPositionManager(positionManager).depositReserves(params); //params must be to send to here

        amounts[0] = GammaSwapLibrary.balanceOf(lpTokens[0], address(this));
        amounts[1] = GammaSwapLibrary.balanceOf(lpTokens[1], address(this));

        if(amounts[0] > 0) GammaSwapLibrary.safeTransfer(lpTokens[0], msg.sender, amounts[0]);
        if(amounts[1] > 0) GammaSwapLibrary.safeTransfer(lpTokens[1], msg.sender, amounts[1]);
    }

    function removeLiquidity(IPositionManager.WithdrawReservesParams calldata params, uint256[] memory amountOutMin, address[] calldata path0, address[] calldata path1, bytes memory uniV3Path0, bytes memory uniV3Path1) external override {
        require(params.to == address(this), "LP_ZAPPER: INVALID_WITHDRAW_TO");
        require(amountOutMin.length == 2, "LP_ZAPPER: INVALID_AMOUNTS_OUT_MIN_LENGTH");
        (uint256[] memory reserves,) = IPositionManager(positionManager).withdrawReserves(params); //params must be to send to here

        address[] memory lpTokens = new address[](2);
        lpTokens[0] = ICPMM10(params.cfmm).token0();
        lpTokens[1] = ICPMM10(params.cfmm).token1();

        if(path0.length > 0 || uniV3Path0.length > 0) {
            if(uniV3Path0.length > 0) {
                _uniV3Swap(lpTokens[0], reserves[0], amountOutMin[0], uniV3Path0, msg.sender);
            } else {
                _swap(lpTokens[0], reserves[0], amountOutMin[0], path0, params.protocolId, msg.sender);
            }
        } else {
            GammaSwapLibrary.safeTransfer(lpTokens[0], msg.sender, reserves[0]);
        }
        if(path1.length > 0 || uniV3Path1.length > 0) {
            if(uniV3Path1.length > 0) {
                _uniV3Swap(lpTokens[1], reserves[1], amountOutMin[1], uniV3Path1, msg.sender);
            } else {
                _swap(lpTokens[1], reserves[1], amountOutMin[1], path1, params.protocolId, msg.sender);
            }
        } else {
            GammaSwapLibrary.safeTransfer(lpTokens[1], msg.sender, reserves[1]);
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

    function _swap(address tokenIn, uint256 amountIn, uint256 amountOutMin, address[] calldata path, uint256 protocolId, address to) internal {
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

        IDeltaSwapRouter10(router).swapExactTokensForTokens(amountIn, amountOutMin, path, to, block.timestamp); // the last amounts is what was obtained
    }

}
